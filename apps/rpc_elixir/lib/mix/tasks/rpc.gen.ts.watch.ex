defmodule Mix.Tasks.Rpc.Gen.Ts.Watch do
  @moduledoc """
  Watches Elixir sources and regenerates the TypeScript client on every change.

  Runs `rpc.gen.ts` once on startup, then re-runs it whenever a `.ex` file
  under the watched directories changes.

  Each regeneration spawns a fresh `mix rpc.gen.ts` process. This is
  deliberate: an in-process `Mix.Task.rerun("compile")` does not pick up source
  edits. The Elixir compiler caches its manifest for the lifetime of the BEAM,
  so it reports `:noop` and the generated client goes stale. A separate process
  re-reads the manifest from disk and recompiles correctly.

  ## Usage

      mix rpc.gen.ts.watch --router MyApp.Router --out path/to/rpc.gen.ts

  Accepts every option `rpc.gen.ts` accepts, plus:

    * `--dir` - a directory to watch (repeatable; defaults to `lib`)

  Requires the optional `:file_system` dependency:

      {:file_system, "~> 1.0", only: :dev}

  """

  use Mix.Task

  @shortdoc "Watch Elixir sources and regenerate the TypeScript client on change"

  @debounce_ms 200

  @impl Mix.Task
  def run(["--help"]), do: Mix.Task.run("help", ["rpc.gen.ts.watch"])
  def run(["-h"]), do: Mix.Task.run("help", ["rpc.gen.ts.watch"])

  def run(args) do
    ensure_file_system!()

    {gen_args, watch_dirs} = split_args(args)

    regenerate(gen_args)

    {:ok, watcher} = FileSystem.start_link(dirs: watch_dirs)
    FileSystem.subscribe(watcher)

    Mix.shell().info("Watching #{Enum.join(watch_dirs, ", ")} for *.ex changes...")
    watch_loop(gen_args)
  end

  defp watch_loop(gen_args) do
    receive do
      {:file_event, _watcher, {path, _events}} ->
        if String.ends_with?(path, ".ex") do
          drain_events()
          regenerate(gen_args)
        end

        watch_loop(gen_args)

      {:file_event, _watcher, :stop} ->
        :ok
    end
  end

  # Wait for a quiet window before regenerating, editors emit several events
  # per save, and a single keystroke can touch many files.
  defp drain_events do
    receive do
      {:file_event, _watcher, _payload} -> drain_events()
    after
      @debounce_ms -> :ok
    end
  end

  defp regenerate(gen_args) do
    {_output, status} =
      System.cmd("mix", ["rpc.gen.ts" | gen_args],
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    if status != 0 do
      Mix.shell().error("[rpc.gen.ts.watch] regeneration failed (exit #{status})")
    end
  end

  defp split_args(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        switches: [router: :string, out: :string, client_import: :string, dir: :keep]
      )

    watch_dirs =
      case Keyword.get_values(opts, :dir) do
        [] -> [Path.expand("lib")]
        dirs -> Enum.map(dirs, &Path.expand/1)
      end

    gen_args = opts |> Keyword.delete(:dir) |> to_argv()

    {gen_args, watch_dirs}
  end

  defp to_argv(opts) do
    Enum.flat_map(opts, fn {key, value} ->
      flag = "--" <> (key |> Atom.to_string() |> String.replace("_", "-"))
      [flag, to_string(value)]
    end)
  end

  defp ensure_file_system! do
    unless Code.ensure_loaded?(FileSystem) do
      Mix.raise("""
      mix rpc.gen.ts.watch requires the :file_system dependency.

      Add it to your deps and run `mix deps.get`:

          {:file_system, "~> 1.0", only: :dev}
      """)
    end
  end
end
