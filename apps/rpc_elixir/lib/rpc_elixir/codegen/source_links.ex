defmodule RpcElixir.Codegen.SourceLinks do
  @moduledoc false
  # Composes a procedure's doc text with a clickable link to the handler source,
  # resolved by reading the handler's BEAM abstract code for the function's line number.

  import RpcElixir.Codegen.Shared, only: [sanitize_doc: 1]

  # A host whose handlers were never compiled to disk has no BEAM to read a line
  # number out of. It puts a `{:ok, display, href}`-returning fun here instead, and
  # the emitted comment keeps the shape it has for a real project.
  @resolver_key :__rpc_source_resolver__

  def handler_jsdoc(proc, indent) do
    doc_text =
      if proc[:doc] && proc[:doc] != "", do: sanitize_doc(String.trim(proc[:doc])), else: nil

    link_comment =
      case handler_location(proc) do
        {:ok, display, href} ->
          mfa = "#{inspect(proc.handler_mod)}.#{proc.handler_fun}/2"
          "[#{display}](#{href}) — `#{mfa}`"

        :error ->
          nil
      end

    case {doc_text, link_comment} do
      {nil, nil} ->
        ""

      {nil, link} ->
        "#{indent}/** #{link} */\n"

      {doc, nil} ->
        "#{indent}/** #{doc} */\n"

      {doc, link} ->
        doc_lines =
          doc
          |> String.split("\n")
          |> Enum.map_join("\n", &"#{indent} * #{&1}")

        "#{indent}/**\n#{doc_lines}\n#{indent} *\n#{indent} * #{link}\n#{indent} */\n"
    end
  end

  defp handler_location(proc) do
    case Process.get(@resolver_key) do
      nil -> beam_location(proc)
      resolver -> resolver.(proc.handler_mod, proc.handler_fun)
    end
  end

  defp beam_location(proc) do
    with {:ok, source_file} <- handler_source_file(proc.handler_mod),
         {:ok, line} <- handler_function_line(proc.handler_mod, proc.handler_fun, 2) do
      {:ok, "#{Path.basename(source_file)}:#{line}", "#{source_file}#L#{line}"}
    else
      _ -> :error
    end
  end

  defp handler_source_file(module) do
    case module.module_info(:compile)[:source] do
      nil ->
        :error

      source ->
        abs = List.to_string(source)
        {:ok, source_link_path(abs)}
    end
  rescue
    _ -> :error
  end

  # For real generation (an output path is known) we emit an absolute `file://`
  # URI: VS Code's link detector makes those clickable in the editor, whereas a
  # relative path is not detected. The generated client is typically gitignored,
  # so absolute paths cause no diff churn. Without an output path (e.g. tests
  # calling generate/1) we emit a deterministic repo-root-relative path so
  # fixtures never contain a machine-specific absolute path.
  defp source_link_path(abs_path) do
    case Process.get(:__rpc_out_dir__) do
      nil -> relative_to_root(abs_path)
      _out_dir -> "file://" <> Path.expand(abs_path)
    end
  end

  defp relative_to_root(abs_path) do
    root = project_root()

    if String.starts_with?(abs_path, root <> "/") do
      String.slice(abs_path, String.length(root) + 1, String.length(abs_path))
    else
      abs_path
    end
  end

  defp project_root do
    case System.cmd("git", ["rev-parse", "--show-toplevel"], stderr_to_stdout: true) do
      {path, 0} -> String.trim(path)
      _ -> File.cwd!()
    end
  end

  defp handler_function_line(module, fun, arity) do
    beam = :code.which(module)

    if beam == :non_existing do
      :error
    else
      case :beam_lib.chunks(beam, [:abstract_code]) do
        {:ok, {_, [{:abstract_code, {:raw_abstract_v1, forms}}]}} ->
          find_function_line(forms, fun, arity)

        {:ok, {_, [{:abstract_code, :no_abstract_code}]}} ->
          track_missing_abstract_code(module)
          :error

        _ ->
          :error
      end
    end
  rescue
    _ -> :error
  end

  defp find_function_line(forms, fun, arity) do
    Enum.find_value(forms, :error, fn
      {:function, loc, ^fun, ^arity, _} ->
        case loc do
          {line, _} when is_integer(line) -> {:ok, line}
          line when is_integer(line) -> {:ok, line}
          _ -> nil
        end

      _ ->
        nil
    end)
  end

  defp track_missing_abstract_code(module) do
    current = Process.get(:__rpc_missing_abstract_code__, [])

    unless module in current do
      Process.put(:__rpc_missing_abstract_code__, [module | current])
    end
  end
end
