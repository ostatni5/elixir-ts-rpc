defmodule RpcElixir.Codegen.Shared do
  @moduledoc false
  # Small helpers shared across the codegen submodules: naming-key construction,
  # property-key emission, IR unwrapping, PaginatedResponse detection, and
  # custom `ts_type/0` resolution.

  @ts_identifier ~r/^[a-zA-Z_$][a-zA-Z0-9_$]*$/

  def proc_base_key(proc), do: "#{inspect(proc.handler_mod)}.#{proc.handler_fun}"

  @doc """
  Error `code`s contributed by a procedure's middleware chain, in attach order
  and de-duplicated. A middleware opts in by implementing
  `c:RpcElixir.Middleware.rpc_error_codes/1`. One that does not implement it contributes none.

  These are folded into the procedure's generated error type and its runtime
  `.isError` codes so cross-cutting errors (e.g. `:unauthorized` from an auth
  middleware) are visible to the client without being repeated in handler specs.
  """
  def middleware_error_codes(%{middleware: middleware}) do
    middleware
    |> Enum.flat_map(fn {mod, opts} ->
      if function_exported?(mod, :rpc_error_codes, 1), do: mod.rpc_error_codes(opts), else: []
    end)
    |> Enum.uniq()
  end

  def middleware_error_codes(_proc), do: []

  def require_name!(name_map, key) do
    case Map.fetch(name_map, key) do
      {:ok, name} -> name
      :error -> raise "Procedure references unknown $defs key: #{key}"
    end
  end

  def emit_prop_key(name) do
    if Regex.match?(@ts_identifier, name), do: name, else: JSON.encode!(name)
  end

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
    if Regex.match?(@ts_identifier, name) do
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
