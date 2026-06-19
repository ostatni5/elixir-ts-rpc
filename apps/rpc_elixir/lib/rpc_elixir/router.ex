defmodule RpcElixir.Router do
  @moduledoc """
  Macro-based DSL for defining RPC procedures in a router module.

  ## Usage

      defmodule MyApp.Router do
        use RpcElixir.Router

        procedure "users.get",    &Hello.Users.get/2
        procedure "users.update", &Hello.Users.update/2, middleware: [MyApp.Middleware.RequireUser]
      end

  Each `procedure` takes a wire name and a remote function capture of arity 2.
  Captures give editors "go to definition" support and enforce arity at the
  call site. Local captures (`&local_fn/2`), captures of other arities, and
  non-capture values raise `CompileError`.

  ## Scoping

  `scope` groups procedures under a shared prefix and/or shared middleware so a
  cross-cutting concern (e.g. authentication) is declared once for the whole
  group instead of repeated on every `procedure`. See `scope/2` and `scope/3`.

      scope "users", middleware: [MyApp.Middleware.RequireUser] do
        procedure "list", &Hello.Users.list/2   # → "users.list"
        procedure "get",  &Hello.Users.get/2    # → "users.get"
      end

  `expose` registers every public, `@spec`'d, arity-2 function of a handler module
  as a procedure named after the function, composing with the enclosing scope. See
  `expose/2`.

      scope "users", middleware: [MyApp.Middleware.RequireUser] do
        expose Hello.Users   # → "users.list", "users.get", ...
      end

  ## Wire aliases

  The `wire_aliases` option maps a source type's `.t()` to a `RpcElixir.CustomType`
  module so it crosses the wire as that custom type project-wide, without per-field
  annotation. For example, `{DateTime, RpcElixir.UnixMillis}` makes every `DateTime`
  serialize as the branded `EpochMillis` number. Aliases are applied at router compile
  time so codegen and runtime agree. The target must implement the
  `RpcElixir.CustomType` behaviour, and a source cannot alias to itself.

      use RpcElixir.Router, wire_aliases: [{DateTime, RpcElixir.UnixMillis}]

  ## Generated functions

  - `__procedures__/0`, returns a list of maps with keys:
    `name`, `handler_mod`, `handler_fun`, `input`, `output`, `error`,
    `middleware`, `doc`, `schema_base`.
    `input`, `output`, and `error` are internal IR maps produced by
    `RpcElixir.Types.FromSpec`.

  - `__manifest__/0`, same list with the `:middleware` key removed.
    Intended for serialisation and codegen. Middleware is server-internal.

  - `__procedures_index__/0`, a `%{name => procedure}` map for O(1) dispatch
    lookup. Same procedure maps as `__procedures__/0`, keyed by `:name`.

  ## Compile-time guarantees

  Every `procedure` call is validated at compile time:

  - The capture must be a remote function capture of arity 2.
  - The handler module must be compilable via `Code.ensure_compiled!/1`.
  - The function must carry a `@spec` in the RPC convention
    `(input, ctx) :: {:ok, output} | {:error, error}`.
  - Procedure names must be unique within a router.

  Violations raise `CompileError` pointing at the offending `procedure` call site.
  """

  alias RpcElixir.Types.FromSpec

  @doc """
  Returns the absolute paths of the router's own source file and every handler
  module's source file, deduplicated.
  """
  @spec source_files(module()) :: [String.t()]
  def source_files(router) do
    handler_mods =
      if function_exported?(router, :__procedures__, 0) do
        router.__procedures__()
        |> Enum.map(& &1.handler_mod)
        |> Enum.uniq()
      else
        []
      end

    [router | handler_mods]
    |> Enum.flat_map(&module_source_file/1)
    |> Enum.uniq()
  end

  defp module_source_file(mod) do
    source =
      try do
        :erlang.get_module_info(mod, :compile)[:source]
      rescue
        ArgumentError -> nil
      end

    case source do
      nil -> []
      path -> [Path.expand(to_string(path))]
    end
  end

  defmacro __using__(opts) do
    aliases =
      opts
      |> Keyword.get(:wire_aliases, [])
      |> expand_wire_aliases_ast(__CALLER__)
      |> normalize_wire_aliases!(__CALLER__)

    quote do
      import RpcElixir.Router,
        only: [procedure: 2, procedure: 3, scope: 2, scope: 3, expose: 1, expose: 2]

      Module.register_attribute(__MODULE__, :rpc_procedures, accumulate: true)
      Module.put_attribute(__MODULE__, :rpc_wire_aliases, unquote(Macro.escape(aliases)))
      Module.put_attribute(__MODULE__, :rpc_scope_stack, [])
      @before_compile RpcElixir.Router
    end
  end

  defp expand_wire_aliases_ast(aliases, caller) when is_list(aliases) do
    Enum.map(aliases, fn
      {source_ast, target_ast} ->
        {Macro.expand(source_ast, caller), Macro.expand(target_ast, caller)}

      other ->
        other
    end)
  end

  defp expand_wire_aliases_ast(other, _caller), do: other

  defp normalize_wire_aliases!(aliases, caller) when is_list(aliases) do
    Map.new(aliases, &validate_wire_alias!(&1, caller))
  end

  defp normalize_wire_aliases!(other, caller) do
    raise CompileError,
      description:
        "wire_aliases must be a list of {source, target} tuples, got: #{inspect(other)}",
      file: caller.file,
      line: caller.line
  end

  defp validate_wire_alias!({source, target}, caller)
       when is_atom(source) and is_atom(target) do
    if source == target do
      raise CompileError,
        description: "wire_aliases entry cannot map a module to itself: #{inspect(source)}",
        file: caller.file,
        line: caller.line
    end

    ensure_wire_alias_module!(source, "source", caller)
    ensure_wire_alias_module!(target, "target", caller)

    unless function_exported?(target, :wire_spec, 0) and function_exported?(target, :serialize, 1) do
      raise CompileError,
        description:
          "wire_aliases target #{inspect(target)} must implement the RpcElixir.CustomType " <>
            "behaviour (wire_spec/0 and serialize/1)",
        file: caller.file,
        line: caller.line
    end

    {source, target}
  end

  defp validate_wire_alias!(other, caller) do
    raise CompileError,
      description:
        "wire_aliases entry must be a {source_module, target_module} tuple, got: #{inspect(other)}",
      file: caller.file,
      line: caller.line
  end

  # Wraps Code.ensure_compiled/1's error tuple into the CompileError the
  # moduledoc promises for wire_aliases violations.
  defp ensure_wire_alias_module!(module, role, caller) do
    case Code.ensure_compiled(module) do
      {:module, _} ->
        :ok

      {:error, reason} ->
        raise CompileError,
          description:
            "wire_aliases #{role} module #{inspect(module)} could not be loaded (#{inspect(reason)})",
          file: caller.file,
          line: caller.line
    end
  end

  defmacro procedure(name, capture_ast, opts \\ []) do
    {handler_mod, fun} = extract_capture!(capture_ast, __CALLER__)
    accumulate(name, handler_mod, fun, opts, __CALLER__)
  end

  defp accumulate(name, handler_mod, fun, opts, caller) do
    quote do
      @rpc_procedures RpcElixir.Router.__scoped_entry__(
                        __MODULE__,
                        unquote(name),
                        unquote(handler_mod),
                        unquote(fun),
                        unquote(opts),
                        unquote(caller.file),
                        unquote(caller.line)
                      )
    end
  end

  @doc """
  Groups the `procedure` calls in the block under a shared prefix and/or shared
  middleware.

  A scope prepends its `:middleware` to every procedure defined inside it (before
  any procedure-specific middleware, so outer-most auth runs first) and, given a
  string prefix, prepends a dotted segment to each inner procedure's wire name.
  Scopes nest. Prefixes concatenate and middleware accumulates outer-to-inner.

      scope "users", middleware: [RequireUser] do
        procedure "list", &Users.list/2   # → "users.list", middleware: [RequireUser]
        procedure "get", &Users.get/2     # → "users.get",  middleware: [RequireUser]
      end

  The prefix is optional, `scope middleware: [RequireUser] do ... end` shares
  middleware without renaming. Procedures outside any scope are unaffected.
  """
  defmacro scope(prefix_or_opts, do: block) do
    {prefix, opts} = split_scope_args(prefix_or_opts)
    build_scope(prefix, opts, block, __CALLER__)
  end

  defmacro scope(prefix, opts, do: block) do
    build_scope(prefix, opts, block, __CALLER__)
  end

  @doc """
  Registers every public, `@spec`'d, arity-2 function of a handler module as a
  procedure, named after the function.

  The module must `use RpcElixir.Handler`. The wire name is the function name,
  combined with any enclosing `scope` prefix. Enclosing scope middleware (and any
  `:middleware` passed here) apply as with `procedure`. Every exposed function
  must follow the RPC contract `(input, ctx) :: {:ok, _} | {:error, _}`. A
  function that doesn't raises a `CompileError`, the same as a hand-written
  `procedure`.

      scope "counter", middleware: [RequireUser] do
        expose Hello.Counter   # → "counter.get", "counter.adjust", ...
      end

  Use this when the module *is* the API surface. Adding a spec'd arity-2 function
  to it then publishes a procedure. Prefer explicit `procedure` calls when the
  exposed surface should be an auditable subset of the module.
  """
  defmacro expose(handler_ast, opts \\ []) do
    caller = __CALLER__

    quote do
      for entry <-
            RpcElixir.Router.__expose_entries__(
              __MODULE__,
              unquote(handler_ast),
              unquote(opts),
              unquote(caller.file),
              unquote(caller.line)
            ) do
        Module.put_attribute(__MODULE__, :rpc_procedures, entry)
      end
    end
  end

  defp split_scope_args(arg) when is_binary(arg), do: {arg, []}
  defp split_scope_args(opts), do: {nil, opts}

  defp build_scope(prefix, opts, block, caller) do
    quote do
      RpcElixir.Router.__push_scope__(
        __MODULE__,
        unquote(prefix),
        unquote(opts),
        unquote(caller.file),
        unquote(caller.line)
      )

      unquote(block)
      RpcElixir.Router.__pop_scope__(__MODULE__)
    end
  end

  @doc false
  def __push_scope__(module, prefix, opts, file, line) do
    validate_scope!(prefix, opts, file, line)
    stack = Module.get_attribute(module, :rpc_scope_stack) || []
    Module.put_attribute(module, :rpc_scope_stack, [{prefix, opts} | stack])
  end

  @doc false
  def __pop_scope__(module) do
    case Module.get_attribute(module, :rpc_scope_stack) || [] do
      [_ | rest] -> Module.put_attribute(module, :rpc_scope_stack, rest)
      [] -> :ok
    end
  end

  @doc false
  def __scoped_entry__(module, name, handler_mod, fun, opts, file, line) do
    stack = Module.get_attribute(module, :rpc_scope_stack) || []
    {scoped_name(stack, name), handler_mod, fun, scoped_opts(stack, opts), file, line}
  end

  # Stack is innermost-first. Outermost prefix/middleware must lead.
  defp scoped_name(stack, name) do
    stack
    |> Enum.reverse()
    |> Enum.flat_map(fn {prefix, _opts} -> List.wrap(prefix) end)
    |> Kernel.++([name])
    |> Enum.join(".")
  end

  defp scoped_opts(stack, opts) do
    scope_middleware =
      stack
      |> Enum.reverse()
      |> Enum.flat_map(fn {_prefix, scope_opts} -> Keyword.get(scope_opts, :middleware, []) end)

    case scope_middleware do
      [] -> opts
      mw -> Keyword.update(opts, :middleware, mw, fn own -> mw ++ own end)
    end
  end

  @doc false
  def __expose_entries__(router_module, handler_module, opts, file, line) do
    ensure_exposable!(handler_module, file, line)
    stack = Module.get_attribute(router_module, :rpc_scope_stack) || []

    funs =
      handler_module.__rpc_specs__()
      |> Enum.filter(fn {{_fun, arity}, _spec} -> arity == 2 end)
      |> Enum.map(fn {{fun, 2}, _spec} -> fun end)
      |> Enum.sort()

    case funs do
      [] ->
        compile_error!(
          "expose #{inspect(handler_module)} found no public arity-2 @spec'd functions to expose",
          file,
          line
        )

      funs ->
        Enum.map(funs, fn fun ->
          name = Atom.to_string(fun)
          {scoped_name(stack, name), handler_module, fun, scoped_opts(stack, opts), file, line}
        end)
    end
  end

  defp ensure_exposable!(handler_module, file, line) do
    Code.ensure_compiled!(handler_module)

    unless function_exported?(handler_module, :__rpc_specs__, 0) do
      compile_error!(
        "expose #{inspect(handler_module)} requires `use RpcElixir.Handler` " <>
          "(no __rpc_specs__/0 found)",
        file,
        line
      )
    end
  end

  defp validate_scope!(prefix, opts, file, line) do
    unless is_nil(prefix) or (is_binary(prefix) and prefix != "") do
      compile_error!(
        "scope prefix must be a non-empty string, got: #{inspect(prefix)}",
        file,
        line
      )
    end

    unless Keyword.keyword?(opts) do
      compile_error!("scope options must be a keyword list, got: #{inspect(opts)}", file, line)
    end

    case Keyword.keys(opts) -- [:middleware] do
      [] ->
        :ok

      unknown ->
        compile_error!(
          "unknown scope option(s): #{inspect(unknown)} (supported: :middleware)",
          file,
          line
        )
    end

    unless is_list(Keyword.get(opts, :middleware, [])) do
      compile_error!(
        "scope :middleware must be a list, got: #{inspect(opts[:middleware])}",
        file,
        line
      )
    end
  end

  defp extract_capture!(
         {:&, _, [{:/, _, [{{:., _, [mod_ast, fun]}, _, []}, arity]}]},
         env
       )
       when is_atom(fun) and arity == 2 do
    {Macro.expand(mod_ast, env), fun}
  end

  defp extract_capture!(
         {:&, _, [{:/, _, [{{:., _, [_mod_ast, fun]}, _, []}, _arity]}]} = ast,
         env
       )
       when is_atom(fun) do
    raise CompileError,
      description: "procedure capture must have arity 2, got: #{Macro.to_string(ast)}",
      file: env.file,
      line: env.line
  end

  defp extract_capture!(other, env) do
    raise CompileError,
      description:
        "expected a remote function capture like &Mod.fun/2, got: #{Macro.to_string(other)}",
      file: env.file,
      line: env.line
  end

  @doc false
  defmacro __before_compile__(env) do
    raw = Module.get_attribute(env.module, :rpc_procedures)
    tuples = Enum.reverse(raw)
    wire_aliases = Module.get_attribute(env.module, :rpc_wire_aliases) || %{}

    resolved_with_meta = Enum.map(tuples, &resolve_one(&1, wire_aliases))

    check_duplicates(resolved_with_meta)

    {procedures_list, manifest_list} =
      Enum.map(resolved_with_meta, fn %{proc: proc} ->
        {proc, Map.delete(proc, :middleware)}
      end)
      |> Enum.unzip()

    procedures = Macro.escape(procedures_list)
    manifest = Macro.escape(manifest_list)
    procedures_index = Macro.escape(Map.new(procedures_list, &{&1.name, &1}))

    quote do
      def __procedures__, do: unquote(procedures)
      def __manifest__, do: unquote(manifest)
      def __procedures_index__, do: unquote(procedures_index)
    end
  end

  defp resolve_one({name, handler_mod, handler_fun, opts, file, line}, wire_aliases) do
    Code.ensure_compiled!(handler_mod)

    unless function_exported?(handler_mod, handler_fun, 2) do
      compile_error!(
        "#{inspect(handler_mod)}.#{handler_fun}/2 must be defined at arity 2",
        file,
        line
      )
    end

    %{input: input, output: output, error: error} =
      case FromSpec.fetch_rpc(handler_mod, handler_fun, wire_aliases) do
        {:ok, types} ->
          types

        {:error, :module_not_found} ->
          compile_error!(
            "module #{inspect(handler_mod)} could not be loaded",
            file,
            line
          )

        {:error, :no_spec} ->
          compile_error!(
            "#{inspect(handler_mod)}.#{handler_fun}/2 has no @spec. " <>
              "Expected: (input, ctx) :: {:ok, output} | {:error, error}",
            file,
            line
          )

        {:error, {:invalid_return, ast}} ->
          compile_error!(
            "#{inspect(handler_mod)}.#{handler_fun}/2 has an invalid return type: " <>
              Macro.to_string(ast),
            file,
            line
          )

        {:error, {:invalid_spec_shape, ast}} ->
          compile_error!(
            "#{inspect(handler_mod)}.#{handler_fun}/2 has an unsupported @spec shape: " <>
              Macro.to_string(ast) <>
              ". Expected a single-clause spec: (input, ctx) :: {:ok, output} | {:error, error}",
            file,
            line
          )
      end

    doc = extract_doc(handler_mod, handler_fun)
    schema_base = "#{inspect(handler_mod)}.#{handler_fun}"
    middleware = normalize_middleware(opts[:middleware] || [], file, line)

    proc = %{
      name: name,
      handler_mod: handler_mod,
      handler_fun: handler_fun,
      input: input,
      output: output,
      error: error,
      middleware: middleware,
      doc: doc,
      schema_base: schema_base
    }

    %{proc: proc, file: file, line: line}
  end

  defp normalize_middleware(list, file, line) when is_list(list) do
    Enum.map(list, &normalize_middleware_entry(&1, file, line))
  end

  defp normalize_middleware(other, file, line) do
    compile_error!(
      "middleware must be a list, got: #{inspect(other)}",
      file,
      line
    )
  end

  defp normalize_middleware_entry(mod, file, line) when is_atom(mod) do
    ensure_middleware_module!(mod, file, line)
    {mod, []}
  end

  defp normalize_middleware_entry({mod, opts}, file, line) when is_atom(mod) do
    ensure_middleware_module!(mod, file, line)
    {mod, opts}
  end

  defp normalize_middleware_entry(other, file, line) do
    compile_error!(
      "middleware entry must be a module or {module, opts} tuple, got: #{inspect(other)}",
      file,
      line
    )
  end

  defp ensure_middleware_module!(mod, file, line) do
    Code.ensure_compiled!(mod)

    unless function_exported?(mod, :call, 2) do
      compile_error!(
        "middleware #{inspect(mod)} must export call/2 (see RpcElixir.Middleware)",
        file,
        line
      )
    end

    # Reject modules that merely happen to export call/2 (e.g. Plugs), they must
    # opt in by declaring `@behaviour RpcElixir.Middleware`.
    unless declares_middleware_behaviour?(mod) do
      compile_error!(
        "middleware #{inspect(mod)} must declare `@behaviour RpcElixir.Middleware`",
        file,
        line
      )
    end
  end

  defp declares_middleware_behaviour?(mod) do
    behaviours = mod.module_info(:attributes)[:behaviour] || []
    RpcElixir.Middleware in behaviours
  end

  defp extract_doc(handler_mod, handler_fun) do
    case Code.fetch_docs(handler_mod) do
      {:docs_v1, _, _, _, _, _, docs} ->
        Enum.find_value(docs, fn
          {{:function, ^handler_fun, 2}, _, _, doc, _} when is_map(doc) ->
            Map.get(doc, "en")

          _ ->
            nil
        end)

      _ ->
        nil
    end
  end

  defp check_duplicates(resolved_with_meta) do
    Enum.reduce(resolved_with_meta, MapSet.new(), fn %{proc: proc, file: file, line: line},
                                                     seen ->
      if MapSet.member?(seen, proc.name) do
        compile_error!(
          "procedure #{inspect(proc.name)} defined more than once in router",
          file,
          line
        )
      end

      MapSet.put(seen, proc.name)
    end)
  end

  defp compile_error!(message, file, line) do
    raise CompileError, description: message, file: file, line: line
  end
end
