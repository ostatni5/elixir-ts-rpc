defmodule RpcElixir.Codegen.Shared do
  @moduledoc false
  # Small helpers shared across the codegen submodules: naming-key construction,
  # property-key emission, IR unwrapping, PaginatedResponse detection, and
  # custom `ts_type/0` resolution.

  alias RpcElixir.JSON

  def proc_base_key(proc), do: "#{inspect(proc.handler_mod)}.#{proc.handler_fun}"

  @doc """
  Error `code`s contributed by a procedure's middleware chain, in attach order
  and de-duplicated. A middleware opts in by implementing
  `c:RpcElixir.Middleware.rpc_error_codes/1`; one that does not implement it contributes none.

  These are folded into the procedure's generated error type and its runtime
  `.isError` codes so cross-cutting errors (e.g. `:unauthorized` from an auth
  middleware) are visible to the client without being repeated in handler specs.
  """
  def middleware_error_codes(%{middleware: middleware}) do
    middleware
    |> Enum.flat_map(fn {mod, opts} ->
      if loaded_and_exports?(mod, :rpc_error_codes, 1),
        do: mod.rpc_error_codes(opts),
        else: []
    end)
    |> Enum.uniq()
  end

  def middleware_error_codes(_proc), do: []

  # `function_exported?/3` answers for LOADED modules only, and codegen runs under
  # a lazily-loading runtime. A middleware module nothing has touched yet reports
  # no exports, so its error codes silently vanished from the generated client:
  # whether they appeared depended on what else happened to load first. Load it
  # before asking. (`custom_ts_type/1` below is safe already, via its own
  # `Code.ensure_compiled/1`.)
  defp loaded_and_exports?(mod, fun, arity) do
    Code.ensure_loaded?(mod) and function_exported?(mod, fun, arity)
  end

  def require_name!(name_map, key) do
    case Map.fetch(name_map, key) do
      {:ok, name} -> name
      :error -> raise "Procedure references unknown $defs key: #{key}"
    end
  end

  def emit_prop_key(name) do
    if ts_identifier?(name), do: name, else: JSON.encode!(name)
  end

  # Hand-rolled instead of a regex because AtomVM has no :re, and codegen also
  # runs in the browser playground.
  defp ts_identifier?(<<first, rest::binary>>), do: id_start?(first) and id_rest?(rest)
  defp ts_identifier?(_), do: false

  defp id_start?(char), do: char in ?a..?z or char in ?A..?Z or char == ?_ or char == ?$

  defp id_rest?(<<>>), do: true

  defp id_rest?(<<char, rest::binary>>),
    do: (id_start?(char) or char in ?0..?9) and id_rest?(rest)

  def unwrap_optional(%{kind: "optional", inner: inner}), do: {inner, true}
  def unwrap_optional(ir), do: {ir, false}

  def last_segment(module), do: module |> Module.split() |> List.last()

  def sanitize_doc(text), do: String.replace(text, "*/", "* /")

  def paginated_item_type(%{
        items: %{kind: "list", inner: inner},
        next_cursor: %{kind: "nullable", inner: %{kind: "primitive", type: "string"}},
        has_more: %{kind: "primitive", type: "boolean"}
      }),
      do: {:ok, inner}

  def paginated_item_type(_), do: :not_paginated

  def custom_ts_type(mod) do
    Code.ensure_compiled(mod)
    if function_exported?(mod, :ts_type, 0), do: validate_ts_type!(mod, mod.ts_type()), else: nil
  end

  defp validate_ts_type!(mod, name) when is_binary(name) do
    if ts_identifier?(name) do
      name
    else
      raise "Codegen: #{inspect(mod)}.ts_type/0 returned #{inspect(name)}, which is not a " <>
              "valid TypeScript identifier (expected something like \"Int64String\")."
    end
  end

  defp validate_ts_type!(mod, other) do
    raise "Codegen: #{inspect(mod)}.ts_type/0 must return a String, got #{inspect(other)}."
  end
end
