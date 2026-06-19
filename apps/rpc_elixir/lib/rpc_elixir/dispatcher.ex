defmodule RpcElixir.Dispatcher do
  @moduledoc """
  Core dispatch pipeline: lookup → middleware → validate input → invoke handler →
  validate output → serialize.

  Every transport (HTTP Plug, in-process caller) funnels through `dispatch/4`,
  which threads a `%RpcElixir.Resolution{}` through the procedure's middleware
  chain and the inner pipeline. The returned resolution carries the final
  outcome on its `:result` field, so middleware that wraps `dispatch/4` can
  observe and transform results uniformly.

  ## Typed handler errors

  When a handler returns `{:error, reason}`, the dispatcher promotes `reason`
  to a top-level `%RpcError{}`:

    - `reason` is an atom: `code = reason`, `message = Atom.to_string(reason)`,
      `details = nil`. HTTP status is derived by the transport from
      `RpcElixir.RpcError`'s framework status map (falling back to a generic
      status).
    - `reason` is a plain map (not a struct) with `:code` (atom): `code =
      reason.code`, `message = reason[:message] || Atom.to_string(code)`,
      `details = reason` minus `:code` and `:message` (or `nil` if empty).
      HTTP status is derived by the transport from `RpcElixir.RpcError`'s
      framework status map (falling back to a generic status).
    - `reason` is already an `%RpcError{}` with a non-nil `:source`: passed
      through unchanged. If `:source` is `nil`, it is stamped with
      `source: :domain` before being returned.
    - Anything else (structs, tuples, keyword lists, lists, …): wrapped as
      `%RpcError{code: :handler_error, details: %{kind: :error, reason:
      inspect(reason)}}` with status 500 (the default status for
      `:handler_error` in `RpcElixir.RpcError.framework_errors/0`). These are
      framework-level "handler returned something unexpected" cases.

  This contract matches the JS `Error` shape on the TypeScript client:
  `err.code`, `err.message`, and `err.details` are all populated for typed
  errors, and `err.message` shows up in stack traces and `console.error`.
  """

  alias RpcElixir.{Resolution, RpcError, Types}

  require Logger

  @typedoc "Final result populated on `Resolution.result` after dispatch."
  @type result :: {:ok, term()} | {:error, RpcError.t()}

  @doc """
  Dispatches a procedure call against `router`, returning the resolution with
  `:result` populated.

  - If the input resolution is already halted, it is returned as-is.
  - If the procedure path is unknown, the result is set to a
    `:procedure_not_found` `RpcError` without invoking middleware.
  - Otherwise, the procedure's middleware chain runs around the inner
    pipeline. Any middleware may halt the resolution to short-circuit.
  """
  @spec dispatch(module(), String.t(), map(), Resolution.t()) :: Resolution.t()
  def dispatch(_router, _path, _raw_input, %Resolution{state: :halted} = resolution) do
    resolution
  end

  def dispatch(router, path, raw_input, %Resolution{} = resolution) do
    case lookup(router, path) do
      {:ok, proc} ->
        resolution
        |> run_middleware(proc.middleware)
        |> apply_handler(proc, raw_input)

      {:error, %RpcError{} = err} ->
        %{resolution | result: {:error, err}}
    end
  end

  defp run_middleware(%Resolution{state: :halted} = res, _middleware), do: res
  defp run_middleware(res, []), do: res

  defp run_middleware(res, [{mod, opts} | rest]) do
    res
    |> mod.call(opts)
    |> run_middleware(rest)
  end

  defp apply_handler(%Resolution{state: :halted} = res, _proc, _raw_input), do: res

  defp apply_handler(%Resolution{result: existing} = res, proc, raw_input)
       when not is_nil(existing) do
    Logger.warning(
      "[rpc_elixir] middleware wrote :result on procedure #{inspect(proc.name)} without halting. " <>
        "It is being clobbered by the handler step. Use Resolution.halt/2 to short-circuit instead."
    )

    apply_handler(%{res | result: nil}, proc, raw_input)
  end

  defp apply_handler(%Resolution{} = res, proc, raw_input) do
    result =
      with {:ok, validated_input} <- validate_input(proc, raw_input),
           {:ok, handler_output} <- invoke(proc, validated_input, res.ctx) do
        validate_and_serialize_output(proc, handler_output)
      end

    %{res | result: result}
  end

  defp lookup(router, path) do
    case Map.fetch(router.__procedures_index__(), path) do
      {:ok, _proc} = ok ->
        ok

      :error ->
        {:error,
         RpcError.framework(
           :procedure_not_found,
           "no procedure registered for path #{inspect(path)}"
         )}
    end
  end

  defp validate_input(proc, raw_input) do
    case Types.validate(proc.input, raw_input) do
      {:ok, _} = ok ->
        ok

      {:error, field_errors} ->
        {:error,
         RpcError.framework(:input_validation_failed, "input validation failed", field_errors)}
    end
  end

  defp invoke(proc, validated_input, ctx) do
    case apply(proc.handler_mod, proc.handler_fun, [validated_input, ctx]) do
      {:ok, _} = ok ->
        ok

      {:error, reason} ->
        {:error, build_typed_error(reason)}

      other ->
        Logger.error(
          "[rpc_elixir] handler #{inspect(proc.handler_mod)}.#{proc.handler_fun} returned unexpected value: #{inspect(other)}"
        )

        {:error, handler_error(:unexpected_return, inspect(other))}
    end
  rescue
    e ->
      Logger.error(
        "[rpc_elixir] handler #{inspect(proc.handler_mod)}.#{proc.handler_fun} raised:\n" <>
          Exception.format(:error, e, __STACKTRACE__)
      )

      {:error, handler_error(:exception, Exception.message(e))}
  end

  @handler_error_messages %{
    unexpected_return: "handler returned an unexpected value",
    exception: "handler raised an exception"
  }

  @handler_error_detail_keys %{unexpected_return: :value, exception: :message}

  defp handler_error(kind, detail) do
    details =
      if expose_error_details?() do
        %{:kind => kind, @handler_error_detail_keys[kind] => detail}
      else
        %{kind: kind}
      end

    RpcError.framework(:handler_error, @handler_error_messages[kind], details)
  end

  defp expose_error_details? do
    Application.get_env(:elixir_ts_rpc, :expose_error_details, false)
  end

  defp build_typed_error(%RpcError{source: nil} = err), do: %{err | source: :domain}
  defp build_typed_error(%RpcError{} = err), do: err

  defp build_typed_error(code) when is_atom(code) and not is_nil(code) do
    %RpcError{code: code, message: Atom.to_string(code), source: :domain}
  end

  defp build_typed_error(%{code: code} = map) when is_atom(code) and not is_struct(map) do
    rest = Map.drop(map, [:code, :message])
    details = if map_size(rest) == 0, do: nil, else: rest
    message = Map.get(map, :message) || Atom.to_string(code)
    %RpcError{code: code, message: message, details: details, source: :domain}
  end

  defp build_typed_error(other) do
    RpcError.framework(:handler_error, "handler returned an error", %{
      kind: :error,
      reason: inspect(other)
    })
  end

  defp validate_and_serialize_output(proc, output) do
    case Types.validate(proc.output, output) do
      {:ok, coerced} ->
        {:ok, Types.serialize(proc.output, coerced)}

      {:error, field_errors} ->
        {:error,
         RpcError.framework(
           :output_validation_failed,
           "output validation failed, this is a server bug",
           field_errors
         )}
    end
  end
end
