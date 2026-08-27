defmodule Playground.Server do
  @moduledoc """
  The playground's Elixir half. Runs inside Popcorn and answers one kind of
  request from the browser: "here is Elixir source, give me the TypeScript
  client that `mix rpc.gen.ts` would generate for it."

  Compiling the router at runtime is not a shortcut, it is the requirement:
  `Code.Typespec.fetch_specs/1` needs reachable debug info, and modules packed
  into the `.avm` have none.
  """

  alias Popcorn.Wasm

  require Popcorn.Wasm

  # Names the editor buffer in generated source links. Not a real file, and it
  # travels with the response so index.js never has to repeat the name.
  @buffer_name "playground.ex"

  def start do
    # Every keystroke recompiles the same module names, so without this every
    # regeneration after the first floods the console with "redefining module".
    Code.put_compiler_option(:ignore_module_conflict, true)
    Wasm.ready(:playground)
    loop()
  end

  defp loop do
    receive do
      raw when Wasm.is_wasm_message(raw) -> Wasm.handle_message!(raw, &handle_message/1)
      _other -> :ok
    end

    loop()
  end

  defp handle_message({:wasm_call, source}) when is_binary(source) do
    {:resolve, generate(source), :ok}
  end

  defp handle_message({:wasm_call, _other}) do
    {:resolve, failure("request", "expected the Elixir source as a string"), :ok}
  end

  defp handle_message(_other), do: :ok

  defp generate(source) do
    with {:ok, modules} <- compile(source),
         {:ok, router} <- find_router(modules) do
      run_codegen(router, handler_lines(source))
    end
  end

  # Every failure below is something a person can type into the editor, so they
  # all have to come back as data. An uncaught raise would take the VM with it
  # and force a page reload.
  defp compile(source) do
    {result, diagnostics} = Code.with_diagnostics([log: true], fn -> compile_string(source) end)

    case result do
      {:ok, modules} -> {:ok, modules}
      failure -> Map.update!(failure, :error, &explain(&1, diagnostics))
    end
  end

  defp compile_string(source) do
    {:ok, Enum.map(Code.compile_string(source), fn {mod, _bin} -> mod end)}
  rescue
    e -> failure("compile", Exception.message(e))
  catch
    kind, reason -> failure("compile", "#{kind}: #{inspect(reason)}")
  end

  # Semantic errors (an undefined function, a missing module) raise nothing more
  # useful than "errors have been logged", and what was logged went to a console
  # nobody has open. The diagnostics are the only copy of the actual reason.
  defp explain(message, diagnostics) do
    case Enum.filter(diagnostics, &(&1.severity == :error)) do
      [] -> message
      errors -> Enum.map_join(errors, "\n", &format_diagnostic/1)
    end
  end

  defp format_diagnostic(%{message: message} = diagnostic) do
    case diagnostic[:position] do
      {line, column} -> "line #{line}:#{column}: #{message}"
      line when is_integer(line) and line > 0 -> "line #{line}: #{message}"
      _ -> message
    end
  end

  defp find_router(modules) do
    case Enum.filter(modules, &function_exported?(&1, :__procedures__, 0)) do
      [router | _] -> {:ok, router}
      [] -> failure("router", "no module in the source `use`s RpcElixir.Router")
    end
  end

  defp run_codegen(router, lines) do
    Process.put(:__rpc_source_resolver__, &source_link(&1, &2, lines))

    %{
      ok: true,
      typescript: RpcElixir.Codegen.generate(router),
      procedures: Enum.map(router.__procedures__(), & &1.name),
      source_file: @buffer_name
    }
  rescue
    e -> failure("codegen", Exception.message(e))
  catch
    kind, reason -> failure("codegen", "#{kind}: #{inspect(reason)}")
  end

  # `mix rpc.gen.ts` links each generated method back to its handler by reading
  # the line out of the handler's BEAM debug info. Nothing here was compiled to
  # disk, so the lines come from the buffer's own AST, and the href names the
  # editor rather than a file the browser could open. index.js intercepts it.
  defp source_link(module, fun, lines) do
    case Map.fetch(lines, {module, fun, 2}) do
      {:ok, line} -> {:ok, "#{@buffer_name}:#{line}", "file:///#{@buffer_name}#L#{line}"}
      :error -> :error
    end
  end

  defp handler_lines(source) do
    case Code.string_to_quoted(source) do
      {:ok, ast} -> collect_module_defs(ast)
      _ -> %{}
    end
  end

  defp collect_module_defs(ast) do
    {_ast, lines} =
      Macro.prewalk(ast, %{}, fn
        {:defmodule, _, [{:__aliases__, _, parts}, [do: body]]} = node, lines ->
          {node, Map.merge(def_lines(body, Module.concat(parts)), lines)}

        node, lines ->
          {node, lines}
      end)

    lines
  end

  defp def_lines(body, module) do
    {_ast, lines} =
      Macro.prewalk(body, %{}, fn
        {:def, meta, [{name, _, args} | _]} = node, lines when is_atom(name) and is_list(args) ->
          {node, Map.put_new(lines, {module, name, length(args)}, meta[:line])}

        node, lines ->
          {node, lines}
      end)

    lines
  end

  defp failure(stage, message), do: %{ok: false, stage: stage, error: message}
end
