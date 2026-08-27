defmodule RpcElixir.Codegen.Tree do
  @moduledoc false
  # Procedure tree (keyed by dotted-name segments, leaves hold the proc) plus
  # the two emitters that walk it: the `RpcClient` type and the
  # `createRpcClient` factory whose leaves are `rpcMethod` calls.

  import RpcElixir.Codegen.Shared

  alias RpcElixir.Codegen.Render
  alias RpcElixir.Codegen.SourceLinks
  alias RpcElixir.JSON

  def build_proc_tree(procedures) do
    Enum.reduce(procedures, %{}, fn proc, acc ->
      segments = String.split(proc.name, ".")
      insert_proc_tree(acc, segments, proc)
    end)
  end

  defp insert_proc_tree(tree, [segment], proc) do
    if is_map(Map.get(tree, segment)) do
      raise ~s(Codegen: name collision: procedure "#{proc.name}" cannot coexist with an existing namespace "#{segment}" — "#{segment}" would be both a leaf method and a namespace. Rename one of them.)
    end

    Map.put(tree, segment, {:leaf, proc})
  end

  defp insert_proc_tree(tree, [segment | rest], proc) do
    case Map.get(tree, segment) do
      {:leaf, existing_proc} ->
        raise ~s(Codegen: name collision: procedure "#{existing_proc.name}" cannot coexist with procedure "#{proc.name}" — "#{segment}" would be both a leaf method and a namespace. Rename one of them.)

      sub ->
        sub = sub || %{}
        Map.put(tree, segment, insert_proc_tree(sub, rest, proc))
    end
  end

  defp walk_tree(tree, name_map, depth, leaf_fn, branch_fn) do
    indent = String.duplicate("  ", depth)

    Enum.map_join(tree, "", fn {segment, node} ->
      case node do
        {:leaf, proc} ->
          leaf_fn.(segment, proc, name_map, indent)

        subtree when is_map(subtree) ->
          inner = walk_tree(subtree, name_map, depth + 1, leaf_fn, branch_fn)
          branch_fn.(segment, inner, indent)
      end
    end)
  end

  def emit_rpc_client_type(proc_tree, name_map) do
    body =
      walk_tree(proc_tree, name_map, 1, &client_type_leaf/4, &client_type_branch/3)

    "export type RpcClient = {\n#{body}};\n"
  end

  defp client_type_leaf(segment, proc, name_map, indent) do
    {input_name, output_name, error_name} = proc_type_names(proc, name_map)
    key = emit_prop_key(segment)
    doc = SourceLinks.handler_jsdoc(proc, indent)

    """
    #{doc}#{indent}#{key}: RpcMethod<#{input_name}, #{output_name}, #{proc_error_type(proc, error_name)}>;
    """
  end

  defp proc_type_names(proc, name_map) do
    base = proc_base_key(proc)

    {
      require_name!(name_map, "#{base}.Input"),
      require_name!(name_map, "#{base}.Output"),
      require_name!(name_map, "#{base}.Error")
    }
  end

  defp client_type_branch(segment, inner, indent) do
    key = emit_prop_key(segment)
    "#{indent}#{key}: {\n#{inner}#{indent}};\n"
  end

  def emit_create_rpc_client(proc_tree, name_map) do
    body = walk_tree(proc_tree, name_map, 2, &create_client_leaf/4, &create_client_branch/3)

    """
    export function createRpcClient(opts: Parameters<typeof createClient>[0]): RpcClient {
      const client: Client = createClient(opts);
      return {
    #{body}  };
    }
    """
  end

  defp create_client_leaf(segment, proc, name_map, indent) do
    {input_name, output_name, error_name} = proc_type_names(proc, name_map)
    key = emit_prop_key(segment)
    doc = SourceLinks.handler_jsdoc(proc, indent)
    codes = error_codes_literal(proc)

    """
    #{doc}#{indent}#{key}: rpcMethod<#{input_name}, #{output_name}, #{proc_error_type(proc, error_name)}>(client, #{JSON.encode!(proc.name)}, #{codes}),
    """
  end

  # The procedure's error type is its handler-declared error union (a
  # `DomainError<…>` alias) widened by any codes its middleware can `halt/2` with
  # (a `MiddlewareError<…>` arm) — `HandlerError | MiddlewareError<"unauthorized">`.
  # The two arms carry distinct `source` literals, so a client `source` check (or
  # an `isDomainError`/`isMiddlewareError` guard) narrows the union at compile
  # time. (`never | MiddlewareError<...>` collapses to `MiddlewareError<...>`, so
  # endpoints with no handler error still surface their middleware errors.)
  defp proc_error_type(proc, error_name) do
    case middleware_error_codes(proc) do
      [] -> error_name
      codes -> "#{error_name} | MiddlewareError<#{Enum.map_join(codes, " | ", &JSON.encode!/1)}>"
    end
  end

  defp error_codes_literal(proc) do
    # error_code_values yields string codes, but middleware codes are atoms — normalize
    # both to strings so a middleware code already in the handler @spec de-dups.
    values =
      (Render.error_code_values(proc.error) ++ middleware_error_codes(proc))
      |> Enum.map(&to_string/1)
      |> Enum.uniq()

    "[" <> Enum.map_join(values, ", ", &JSON.encode!/1) <> "]"
  end

  defp create_client_branch(segment, inner, indent) do
    key = emit_prop_key(segment)
    "#{indent}#{key}: {\n#{inner}#{indent}},\n"
  end
end
