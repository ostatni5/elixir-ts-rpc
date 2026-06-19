defmodule RpcElixir.Types.FromSpec do
  @moduledoc """
  Reads classic `@spec` declarations from a compiled module's BEAM debug info
  (via `Code.Typespec`) and translates them into the internal `%{kind: ...}`
  representation used by handlers, routers, and codegen.

  Users write `@spec` next to their RPC handlers. `FromSpec` reads them at
  runtime, no compile-time macro is required to capture AST.

  Note: `Code.Typespec` is `@moduledoc false` in Elixir core. It has been
  stable in practice for many years and is consumed by ExDoc and dialyzer
  tooling, but the API is not officially committed.

  See `RpcElixir.Types.FromInferred` for an experimental backend that reads
  Elixir's set-theoretic inferred signatures instead.
  """

  alias RpcElixir.Types.RpcConvention
  alias RpcElixir.Types.Walker

  @doc """
  Reads the spec for `module.function/arity` and returns
  `{:ok, %{args: [input_type, ctx_ast, ...], return_ast: ast, local_types: map}}`.

  Only the first arg (the RPC `input`) is translated to the internal type
  representation, it is the sole arg in the wire contract. The remaining args
  (the server-side `ctx`) are returned as raw AST and never walked, so a handler
  may type `ctx` as a non-wire type. The return is likewise left as raw AST
  because handler-style returns (`{:ok, T} | {:error, E}`) must be decomposed by
  tag before walking, caller decides what to do with it.

  Returns `{:error, :no_spec}` if no `@spec` is attached to the function,
  `{:error, :module_not_found}` if the module cannot be loaded, or
  `{:error, {:invalid_spec_shape, ast}}` if the `@spec` is not the expected
  single-clause `fun(args) :: return` shape (e.g. a multi-clause spec).
  """
  @spec fetch_spec(module(), atom(), non_neg_integer()) ::
          {:ok,
           %{
             args: [RpcElixir.Types.internal_spec() | Macro.t()],
             return_ast: term(),
             local_types: map()
           }}
          | {:error, :no_spec}
          | {:error, :module_not_found}
          | {:error, {:invalid_spec_shape, term()}}
  def fetch_spec(module, function, arity), do: fetch_spec(module, function, arity, %{})

  @doc """
  Like `fetch_spec/3`, but resolves source-module `.t()` calls through
  `wire_aliases` (`%{source => target_custom_type}`). The aliases are threaded
  into the `Walker.Ctx` so that codegen and runtime read the same frozen IR.
  """
  @spec fetch_spec(module(), atom(), non_neg_integer(), map()) ::
          {:ok,
           %{
             args: [RpcElixir.Types.internal_spec() | Macro.t()],
             return_ast: term(),
             local_types: map()
           }}
          | {:error, :no_spec}
          | {:error, :module_not_found}
          | {:error, {:invalid_spec_shape, term()}}
  def fetch_spec(module, function, arity, wire_aliases)
      when is_atom(module) and is_atom(function) and is_integer(arity) and is_map(wire_aliases) do
    case Code.ensure_compiled(module) do
      {:error, _} ->
        {:error, :module_not_found}

      {:module, _} ->
        with {:ok, quoted_ast} <- find_spec(module, function, arity),
             {:ok, {args_ast, return_ast}} <- decompose_spec(function, quoted_ast) do
          local_types = load_local_types(module)
          ctx = %Walker.Ctx{local_types: local_types, wire_aliases: wire_aliases}
          args = walk_contract_args(args_ast, ctx)
          {:ok, %{args: args, return_ast: return_ast, local_types: local_types}}
        end
    end
  end

  @doc """
  Convenience for the RPC convention `call(input, context) :: {:ok, output} | {:error, error}`.

  Returns `{:ok, %{input: t, output: t, error: t | nil}}` on success,
  `{:error, :no_spec}` if the function has no `@spec`,
  `{:error, :module_not_found}` if the module cannot be loaded,
  `{:error, {:invalid_spec_shape, ast}}` if the `@spec` is not a single-clause
  `fun(args) :: return`, or
  `{:error, {:invalid_return, return_ast}}` if the return type lacks an `{:ok, _}` variant.
  """
  @spec fetch_rpc(module(), atom()) ::
          {:ok,
           %{
             input: RpcElixir.Types.internal_spec(),
             output: RpcElixir.Types.internal_spec(),
             error: RpcElixir.Types.internal_spec() | nil
           }}
          | {:error, :no_spec}
          | {:error, :module_not_found}
          | {:error, {:invalid_spec_shape, term()}}
          | {:error, {:invalid_return, term()}}
  def fetch_rpc(module, function), do: fetch_rpc(module, function, %{})

  @doc """
  Same as `fetch_rpc/2`, applying `wire_aliases` while resolving types.

  `wire_aliases` maps a source module to a `RpcElixir.CustomType` target (e.g.
  `%{DateTime => RpcElixir.UnixMillis}`) so the source's `.t()` crosses the wire
  as the target custom type. This is the form the router calls.
  """
  @spec fetch_rpc(module(), atom(), map()) ::
          {:ok,
           %{
             input: RpcElixir.Types.internal_spec(),
             output: RpcElixir.Types.internal_spec(),
             error: RpcElixir.Types.internal_spec() | nil
           }}
          | {:error, :no_spec}
          | {:error, :module_not_found}
          | {:error, {:invalid_spec_shape, term()}}
          | {:error, {:invalid_return, term()}}
  def fetch_rpc(module, function, wire_aliases) when is_map(wire_aliases) do
    with {:ok, %{args: [input, _ctx], return_ast: return_ast, local_types: local_types}} <-
           fetch_spec(module, function, 2, wire_aliases) do
      ctx = %Walker.Ctx{local_types: local_types, wire_aliases: wire_aliases}

      case RpcConvention.decompose_return(return_ast) do
        {:error, :no_ok_variant} ->
          {:error, {:invalid_return, return_ast}}

        {:ok, {output_ast, error_ast}} ->
          {:ok,
           %{
             input: input,
             output: Walker.walk(output_ast, ctx),
             error: error_ast && Walker.walk(error_ast, ctx)
           }}
      end
    end
  end

  # Only the first arg, the RPC `input`, is part of the wire contract, so it is
  # the only one translated to the internal type representation. The remaining args
  # (the server-side `ctx`) are never validated or serialized and never reach
  # codegen, so they are returned as raw AST. This lets a handler type its `ctx`
  # as a non-wire type (e.g. `RpcElixir.Context.t()`) without it having to be
  # wire-serializable.
  # The empty clause guards the arity-0 `fetch_spec` call path (`fun() :: x`),
  # the RPC contract itself is always arity-2, so it never hits this in practice.
  defp walk_contract_args([], _ctx), do: []

  defp walk_contract_args([input_ast | rest_ast], ctx) do
    [Walker.walk(input_ast, ctx) | rest_ast]
  end

  defp find_spec(module, function, arity) do
    # Preferred: handler used `use RpcElixir.Handler`, specs are in-module.
    # This avoids the on-disk BEAM dependency that breaks single-Mix-project setups.
    if function_exported?(module, :__rpc_specs__, 0) do
      case Map.get(module.__rpc_specs__(), {function, arity}) do
        nil -> {:error, :no_spec}
        ast -> {:ok, ast}
      end
    else
      with {:ok, specs} <- Code.Typespec.fetch_specs(module),
           {_, [spec_ast | _]} <-
             Enum.find(specs, fn {{n, a}, _} -> n == function and a == arity end) do
        {:ok, Code.Typespec.spec_to_quoted(function, spec_ast)}
      else
        _ -> {:error, :no_spec}
      end
    end
  end

  defp decompose_spec(function, quoted_ast) do
    case quoted_ast do
      # matches: function(args) :: return
      {:"::", _, [{^function, _, args}, return]} when is_list(args) ->
        {:ok, {args, return}}

      # matches: function(args) :: return when var: t, ...
      {:when, _, [{:"::", _, [{^function, _, args}, return]}, bindings]} when is_list(args) ->
        {:ok, inline_bounded_fun_bindings(args, return, bindings)}

      other ->
        {:error, {:invalid_spec_shape, other}}
    end
  end

  defp load_local_types(module) do
    if function_exported?(module, :__rpc_types__, 0) do
      module.__rpc_types__()
    else
      case Code.Typespec.fetch_types(module) do
        {:ok, types} ->
          types
          |> Enum.flat_map(&local_type_entry/1)
          |> Map.new()

        :error ->
          %{}
      end
    end
  end

  # BEAM AST uses `{name, nil, nil}` for zero-arity types and `{name, _, [vars]}` for parameterized ones.
  defp local_type_entry({kind, type_data}) when kind in [:type, :typep, :opaque] do
    case Code.Typespec.type_to_quoted(type_data) do
      # matches: @type name :: body
      {:"::", _, [{name, nil, nil}, body]} when is_atom(name) ->
        [{{name, 0}, {[], body}}]

      # matches: @type name(v1, v2) :: body
      {:"::", _, [{name, _, var_asts}, body]} when is_atom(name) and is_list(var_asts) ->
        var_names = Enum.map(var_asts, fn {v, _, _} -> v end)
        [{{name, length(var_names)}, {var_names, body}}]

      _ ->
        []
    end
  end

  defp local_type_entry(_), do: []

  defp inline_bounded_fun_bindings(args, return, bindings) do
    {Enum.map(args, &Walker.substitute_vars(&1, bindings)),
     Walker.substitute_vars(return, bindings)}
  end
end
