defmodule RpcElixir.Handler do
  @moduledoc """
  Captures `@spec` and `@type` ASTs at handler-compile time. Exposes them
  through the `__rpc_specs__/0` and `__rpc_types__/0` accessors.

  ## Why this exists

  `RpcElixir.Router` validates handler signatures inside `__before_compile__`.
  By default it reads specs from the handler's BEAM file. That path uses
  `Code.Typespec.fetch_specs/1`, which needs the BEAM on disk. Inside a single
  Mix project, the parallel compiler may run the router hook too early.
  In-progress handler BEAMs are not flushed yet. The result is a spurious
  "no @spec" error.

  `use RpcElixir.Handler` avoids this. It captures the spec ASTs into a
  generated function. `RpcElixir.Types.FromSpec` prefers that accessor when it
  exists. The function call is also a compiler dependency edge. So the parallel
  compiler finishes the handler module first. The BEAM need not be on disk.

  Without `use`, the framework still works. But the handler must then live in a
  separate Mix `path:` dep. Its BEAM lands on disk first that way.

  `RpcElixir.Router.expose/2` also requires it. Exposing a module reads its
  surface from `__rpc_specs__/0`, so a handler without `use` raises there.

  Handler input arrives with atom keys. See `RpcElixir.Types.validate/2`. For a
  handler example, see [Getting started](getting-started.md).
  """

  @doc """
  Sets up spec capture for a handler module.

  Generates `__rpc_specs__/0` and `__rpc_types__/0` from the module's `@spec`
  and `@type` attributes.
  """
  defmacro __using__(_opts) do
    quote do
      @before_compile RpcElixir.Handler
    end
  end

  defmacro __before_compile__(env) do
    specs =
      env.module
      |> collect_specs()
      |> Map.filter(fn {{name, arity}, _ast} ->
        arity in [1, 2] and Module.defines?(env.module, {name, arity}, :def)
      end)

    types = collect_types(env.module)

    quote do
      @doc false
      def __rpc_specs__, do: unquote(Macro.escape(specs))

      @doc false
      def __rpc_types__, do: unquote(Macro.escape(types))
    end
  end

  defp collect_specs(module) do
    (Module.get_attribute(module, :spec) || [])
    |> Enum.flat_map(&spec_entry/1)
    |> Map.new()
  end

  # @spec foo(arg1, arg2) :: return
  defp spec_entry({:spec, {:"::", meta, [{name, m2, args}, return]}, _})
       when is_atom(name) and is_list(args) do
    stripped = {:"::", meta, [{name, m2, Enum.map(args, &strip_named_arg/1)}, return]}
    [{{name, length(args)}, stripped}]
  end

  # @spec foo(arg1, arg2) :: return when v1: t, ...
  defp spec_entry(
         {:spec, {:when, when_meta, [{:"::", spec_meta, [{name, m2, args}, return]}, bindings]},
          _}
       )
       when is_atom(name) and is_list(args) do
    stripped =
      {:when, when_meta,
       [
         {:"::", spec_meta, [{name, m2, Enum.map(args, &strip_named_arg/1)}, return]},
         bindings
       ]}

    [{{name, length(args)}, stripped}]
  end

  defp spec_entry(_), do: []

  # `Code.Typespec.spec_to_quoted/2` discards `name ::` arg labels, but the raw
  # AST in `Module.get_attribute(:spec)` keeps them. Strip them here so both
  # paths through `FromSpec` see the same shape.
  defp strip_named_arg({:"::", _, [{name, _, ctx}, type]}) when is_atom(name) and is_atom(ctx),
    do: type

  defp strip_named_arg(other), do: other

  defp collect_types(module) do
    for kind <- [:type, :typep, :opaque],
        entry <- Module.get_attribute(module, kind) || [],
        result <- type_entry(kind, entry),
        into: %{},
        do: result
  end

  # @type name :: body — zero-arity, var ctx is an atom (e.g. nil or Elixir env)
  defp type_entry(kind, {kind, {:"::", _, [{name, _, ctx}, body]}, _})
       when is_atom(name) and is_atom(ctx) do
    [{{name, 0}, {[], body}}]
  end

  # @type name(v1, v2) :: body
  defp type_entry(kind, {kind, {:"::", _, [{name, _, var_asts}, body]}, _})
       when is_atom(name) and is_list(var_asts) do
    var_names = Enum.map(var_asts, fn {v, _, _} -> v end)
    [{{name, length(var_names)}, {var_names, body}}]
  end

  defp type_entry(_kind, _), do: []
end
