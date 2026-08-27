defmodule RpcElixir.Types.Walker do
  @moduledoc false

  alias RpcElixir.Types.Builtins

  defmodule Ctx do
    @moduledoc false
    # Threaded through every `walk/2` call instead of the process dictionary:
    #   * local_types  — the current module's `@type` definitions, for resolving local type calls
    #   * wire_aliases — `%{source_module => target_custom_type}` overrides for `.t()` resolution
    #   * resolving    — per-resolution-path stack of modules, for recursive-type cycle detection
    #
    # `resolving` rides the call stack: each frame pushes onto its own immutable copy
    # before descending, so the "pop" on return is free and sibling branches of a
    # diamond never observe each other's pushes.
    @type t :: %__MODULE__{local_types: map(), wire_aliases: map(), resolving: [module()]}
    defstruct local_types: %{}, wire_aliases: %{}, resolving: []
  end

  @spec walk(Macro.t(), Ctx.t()) :: map()
  def walk(ast, ctx \\ %Ctx{})

  # matches: Some.Module.t()
  def walk({{:., _, [{:__aliases__, _, segments}, :t]}, _, []}, ctx) do
    resolve_t_call(Module.concat(segments), ctx)
  end

  # matches: <atom-module>.t() — when the alias has already been resolved to an atom
  def walk({{:., _, [module, :t]}, _, []}, ctx) when is_atom(module) do
    resolve_t_call(module, ctx)
  end

  # Self-reference sentinel injected by `local_self_ref/1` for a struct's own bare
  # `t()`. Resolves straight to a truncated reference so recursion terminates.
  def walk({:__rpc_self_ref__, module}, _ctx) when is_atom(module),
    do: truncated_struct_ref(module)

  def walk({:binary, _, []}, _ctx), do: %{kind: "primitive", type: "string"}

  def walk({int, _, []}, _ctx) when int in [:integer, :non_neg_integer, :pos_integer],
    do: %{kind: "primitive", type: "integer"}

  def walk({:number, _, []}, _ctx), do: %{kind: "primitive", type: "float"}
  def walk({:float, _, []}, _ctx), do: %{kind: "primitive", type: "float"}
  def walk({:boolean, _, []}, _ctx), do: %{kind: "primitive", type: "boolean"}

  def walk({t, _, []}, _ctx) when t in [:any, :term] do
    raise ArgumentError,
          "#{t}() is not allowed in RPC specs — every field must have an explicit type. " <>
            "Replace with a concrete type, a struct with `@type t`, or a custom type module."
  end

  def walk({:map, _, []}, _ctx) do
    raise ArgumentError,
          "map() is not allowed in RPC specs — use an explicit map shape like " <>
            "`%{key: String.t(), count: integer()}` instead."
  end

  # matches: a | b | c (union)
  def walk({:|, _, [_, _]} = union, ctx) do
    union |> collect_union_variants() |> build_union(union, ctx)
  end

  # matches: [inner] (list literal) and list(inner)
  def walk([inner], ctx), do: %{kind: "list", inner: walk(inner, ctx)}
  def walk({:list, _, [inner]}, ctx), do: %{kind: "list", inner: walk(inner, ctx)}

  # matches: %{key: value, ...}
  def walk({:%{}, _, pairs}, ctx) do
    fields = Map.new(pairs, &map_pair(&1, ctx))
    %{kind: "object", fields: fields}
  end

  # matches: %SomeStruct{field: type, ...}
  def walk({:%, _, [module, {:%{}, _, pairs}]}, ctx) when is_atom(module) do
    resolve_struct(module, pairs, ctx)
  end

  def walk(atom, _ctx) when is_atom(atom) and atom not in [nil, true, false] do
    %{kind: "enum", values: [Atom.to_string(atom)]}
  end

  # matches: name(args) — local @type call (e.g. `my_type(integer())`)
  def walk({name, _, args}, ctx) when is_atom(name) and is_list(args) do
    arity = length(args)

    case Map.get(ctx.local_types, {name, arity}) do
      {var_names, body} ->
        subs = Map.new(Enum.zip(var_names, args))
        walk(substitute_vars(body, subs), ctx)

      nil ->
        raise ArgumentError,
              "unsupported typespec form: #{name}/#{arity} — local @type not found " <>
                "(define `@type #{name}#{type_arity_hint(arity)} :: ...` in this module)"
    end
  end

  def walk(other, _ctx) do
    raise ArgumentError, "unsupported typespec form: #{Macro.to_string(other)}"
  end

  @doc false
  def collect_union_variants({:|, _, [l, r]}),
    do: collect_union_variants(l) ++ collect_union_variants(r)

  def collect_union_variants(other), do: [other]

  @doc false
  def substitute_vars(ast, subs) when is_list(subs), do: substitute_vars(ast, Map.new(subs))

  # Iterate to a fixed point so chained bindings (e.g. `when a: b, b: integer()`)
  # fully resolve. The cap catches circular user bindings.
  def substitute_vars(ast, subs) when is_map(subs) do
    substitute_until_fixed(ast, subs, 16)
  end

  defp substitute_until_fixed(_ast, _subs, 0) do
    raise ArgumentError,
          "substitute_vars exceeded 16 iterations — circular type variable bindings detected"
  end

  defp substitute_until_fixed(ast, subs, remaining) do
    result = do_substitute(ast, subs)
    if result == ast, do: result, else: substitute_until_fixed(result, subs, remaining - 1)
  end

  defp do_substitute({var_name, meta, ctx}, subs) when is_atom(var_name) and not is_list(ctx) do
    case Map.fetch(subs, var_name) do
      {:ok, replacement} -> replacement
      :error -> {var_name, meta, ctx}
    end
  end

  defp do_substitute({op, meta, children}, subs) when is_list(children) do
    {op, meta, Enum.map(children, &do_substitute(&1, subs))}
  end

  defp do_substitute({a, b}, subs) do
    {do_substitute(a, subs), do_substitute(b, subs)}
  end

  defp do_substitute(list, subs) when is_list(list) do
    Enum.map(list, &do_substitute(&1, subs))
  end

  defp do_substitute(node, _subs), do: node

  defp type_arity_hint(0), do: ""
  defp type_arity_hint(n), do: "(#{Enum.map_join(1..n, ", ", fn _ -> "_" end)})"

  defp build_union(variants, union, ctx) do
    cond do
      nil in variants ->
        inner_variants = Enum.reject(variants, &is_nil/1)
        %{kind: "nullable", inner: union_from_variants(inner_variants, ctx)}

      Enum.all?(variants, &literal_atom?/1) ->
        %{kind: "enum", values: Enum.map(variants, &Atom.to_string/1)}

      true ->
        raise ArgumentError,
              "unsupported union in @spec: #{Macro.to_string(union)} " <>
                "(only `T | nil` and atom literal unions are supported — use `@rpc` override for other forms)"
    end
  end

  # %SomeStruct{} with no inline overrides is equivalent to SomeStruct.t() — delegate to type resolution.
  defp resolve_struct(module, [], ctx), do: resolve_t_call(module, ctx)

  defp resolve_struct(module, pairs, ctx) do
    fields = Map.new(pairs, &map_pair(&1, ctx))
    %{kind: "object", fields: fields, struct: module}
  end

  defp resolve_t_call(module, ctx) do
    case wire_alias_for(module, ctx) do
      {:ok, target} -> %{kind: "custom", module: target, inner: target.wire_spec()}
      :none -> resolve_t_call_builtin(module, ctx)
    end
  end

  defp wire_alias_for(module, ctx) do
    case ctx.wire_aliases do
      %{^module => target} -> {:ok, target}
      _ -> :none
    end
  end

  defp resolve_t_call_builtin(String, _ctx), do: %{kind: "primitive", type: "string"}

  defp resolve_t_call_builtin(module, ctx) do
    case Builtins.by_module(module) do
      %{kind: kind} -> %{kind: kind}
      nil -> resolve_t_call_module(module, ctx)
    end
  end

  defp resolve_t_call_module(module, ctx) do
    Code.ensure_compiled(module)

    cond do
      custom_type?(module) -> %{kind: "custom", module: module, inner: module.wire_spec()}
      function_exported?(module, :__schema__, 1) -> ecto_schema_fields(module, ctx)
      true -> resolve_t_from_beam(module, ctx)
    end
  end

  # Recursive struct types (self-referential like `Tree`, or mutually-recursive
  # A.t() ↔ B.t()) are supported by returning a *reference* at the cycle point —
  # a truncated struct marker with empty fields. The full field set comes from the
  # first (outermost) occurrence of the struct in the IR tree. Codegen emits that as
  # a named `export interface` and renders every reference (full or truncated) as the
  # interface name, which TypeScript supports natively for recursive interfaces.
  #
  # Each module is pushed onto a per-resolution-path stack so a diamond A→B,C→D still
  # resolves correctly (D is popped after each branch and is never on the stack twice
  # simultaneously). A non-struct degenerate cycle has nothing to anchor a named type
  # to, so it still raises.
  defp resolve_t_from_beam(module, ctx) do
    cond do
      module in ctx.resolving and struct_module?(module) ->
        truncated_struct_ref(module)

      module in ctx.resolving ->
        raise ArgumentError,
              "cannot resolve #{inspect(module)}.t() — recursive type detected " <>
                "(a type that refers back to itself, directly or via another module). " <>
                "Recursive types are not supported in RPC specs " <>
                "— only struct-based recursive types are supported."

      true ->
        resolve_t_from_beam_uncached(module, ctx)
    end
  end

  defp resolve_t_from_beam_uncached(module, ctx) do
    inner_ctx = %{ctx | local_types: local_self_ref(module), resolving: [module | ctx.resolving]}

    with {:ok, types} <- Code.Typespec.fetch_types(module),
         {_kind, {:t, type_ast, _vars}} <-
           Enum.find(types, fn {_k, {name, _, _}} -> name == :t end),
         # matches: t() :: rhs — we only care about the rhs body
         {:"::", _, [_lhs, rhs]} <- Code.Typespec.type_to_quoted({:t, type_ast, []}) do
      attach_struct_if_object(walk(rhs, inner_ctx), module)
    else
      _ -> raise_struct_error(module)
    end
  end

  defp struct_module?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__struct__, 0)
  end

  defp truncated_struct_ref(module), do: %{kind: "object", struct: module, fields: %{}}

  # A struct's own body can reference itself via bare `t()` (e.g. `Tree`:
  # `children: [t()]`). Bind that zero-arity local type to a sentinel the
  # local-type `walk/2` clause maps straight to a truncated self-reference,
  # WITHOUT re-walking the struct body (which would recurse forever).
  # Non-struct modules get no self binding, so their bare `t()` still errors.
  defp local_self_ref(module) do
    if struct_module?(module),
      do: %{{:t, 0} => {[], {:__rpc_self_ref__, module}}},
      else: %{}
  end

  defp custom_type?(module) do
    function_exported?(module, :wire_spec, 0) and function_exported?(module, :serialize, 1)
  end

  defp ecto_schema_fields(module, ctx) do
    fields =
      Map.new(module.__schema__(:fields), fn name ->
        {name, ecto_type_to_internal(module.__schema__(:type, name), ctx)}
      end)

    %{kind: "object", fields: fields, struct: module}
  end

  defp primitive(type), do: %{kind: "primitive", type: type}

  defp ecto_type_to_internal(:string, _ctx), do: primitive("string")
  defp ecto_type_to_internal(:id, _ctx), do: primitive("integer")
  defp ecto_type_to_internal(:integer, _ctx), do: primitive("integer")
  defp ecto_type_to_internal(:float, _ctx), do: primitive("float")
  defp ecto_type_to_internal(:boolean, _ctx), do: primitive("boolean")
  defp ecto_type_to_internal(:binary_id, _ctx), do: primitive("string")
  defp ecto_type_to_internal(:naive_datetime, ctx), do: resolve_t_call(NaiveDateTime, ctx)
  defp ecto_type_to_internal(:naive_datetime_usec, ctx), do: resolve_t_call(NaiveDateTime, ctx)
  defp ecto_type_to_internal(:utc_datetime, ctx), do: resolve_t_call(DateTime, ctx)
  defp ecto_type_to_internal(:utc_datetime_usec, ctx), do: resolve_t_call(DateTime, ctx)
  defp ecto_type_to_internal(:date, ctx), do: resolve_t_call(Date, ctx)
  defp ecto_type_to_internal(:time, ctx), do: resolve_t_call(Time, ctx)
  defp ecto_type_to_internal(:decimal, ctx), do: resolve_t_call(Decimal, ctx)

  defp ecto_type_to_internal(:map, _ctx) do
    raise ArgumentError,
          "Ecto field type :map is not allowed in RPC specs — " <>
            "replace with an embedded schema or an explicit %{key: type} shape."
  end

  defp ecto_type_to_internal({:array, inner}, ctx),
    do: %{kind: "list", inner: ecto_type_to_internal(inner, ctx)}

  defp ecto_type_to_internal(other, _ctx) do
    raise ArgumentError, "unsupported Ecto field type: #{inspect(other)}"
  end

  defp attach_struct_if_object(%{kind: "object"} = obj, module), do: Map.put(obj, :struct, module)
  defp attach_struct_if_object(other, _module), do: other

  defp raise_struct_error(module) do
    raise ArgumentError,
          "cannot resolve #{inspect(module)}.t() / %#{inspect(module)}{} from @spec — " <>
            "write inline field types (`%#{inspect(module)}{id: integer(), ...}`) " <>
            "or define `@type t :: %__MODULE__{...}` in #{inspect(module)}"
  end

  defp union_from_variants([single], ctx), do: walk(single, ctx)

  defp union_from_variants(many, _ctx) when is_list(many) do
    if Enum.all?(many, &literal_atom?/1) do
      %{kind: "enum", values: Enum.map(many, &Atom.to_string/1)}
    else
      raise ArgumentError, "unsupported non-nullable union: #{Macro.to_string({:|, [], many})}"
    end
  end

  defp literal_atom?(a) when is_atom(a) and a not in [nil, true, false], do: true
  defp literal_atom?(_), do: false

  defp map_pair({{:optional, _, [key]}, value}, ctx) when is_atom(key),
    do: {key, %{kind: "optional", inner: walk(value, ctx)}}

  defp map_pair({{:required, _, [key]}, value}, ctx) when is_atom(key),
    do: {key, walk(value, ctx)}

  defp map_pair({key, value}, ctx) when is_atom(key),
    do: {key, walk(value, ctx)}

  defp map_pair(other, _ctx) do
    raise ArgumentError, "unsupported map entry in @spec: #{Macro.to_string(other)}"
  end
end
