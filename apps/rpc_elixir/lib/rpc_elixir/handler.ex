defmodule RpcElixir.Handler do
  @moduledoc """
  Captures `@spec` and `@type` ASTs at handler-compile time and exposes them
  via `__rpc_specs__/0` / `__rpc_types__/0` accessors.

  ## Why this exists

  `RpcElixir.Router` validates handler signatures inside `__before_compile__`.
  By default it reads them from the handler's BEAM file via
  `Code.Typespec.fetch_specs/1`, which only works after the BEAM is on disk.
  Inside a single Mix project, the parallel compiler may run the router's
  compile-time hook before in-progress handler BEAMs are flushed, producing
  spurious "no @spec" errors.

  When a handler does `use RpcElixir.Handler`, this macro captures the spec
  ASTs into a generated function. The router (via `RpcElixir.Types.FromSpec`)
  prefers that accessor when it exists, and the resulting function-call edge
  forces the parallel compiler to fully compile the handler module before
  using it, without requiring the BEAM to be on disk.

  Without `use RpcElixir.Handler`, the framework still works but requires the
  handler to live in a separate Mix `path:` dep so its BEAM is on disk first.

  ## Input keys are atoms

  The `input` argument received by every handler function has **atom keys**
  (e.g. `%{id: "abc"}`), never string keys. Pattern-match and access
  accordingly:

      def get(%{id: id}, _ctx), do: ...   # correct
      def get(%{"id" => id}, _ctx), do: ... # wrong, key will be absent

  ## Usage

      defmodule MyApp.Handlers.Users do
        use RpcElixir.Handler

        @spec list(input :: %{}, ctx :: map()) :: {:ok, %{users: [%{id: String.t()}]}}
        def list(_input, _ctx), do: {:ok, %{users: []}}
      end
  """

  defmacro __using__(_opts) do
    quote do
      @before_compile RpcElixir.Handler
    end
  end

  defmacro __before_compile__(env) do
    public_defs = MapSet.new(Module.definitions_in(env.module, :def))

    specs =
      env.module
      |> collect_specs()
      |> Map.filter(fn {{name, arity}, _ast} ->
        arity in [1, 2] and MapSet.member?(public_defs, {name, arity})
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

  # @type name :: body, zero-arity, var ctx is an atom (e.g. nil or Elixir env)
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
