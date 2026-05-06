defmodule Mix.Tasks.Rpc.Gen.Ts do
  @moduledoc """
  Generates a TypeScript client file directly from an RPC router module.

  ## Usage

      mix rpc.gen.ts --router MyApp.Router --out path/to/rpc.gen.ts

  ## Options

    * `--router` - (required) the fully-qualified router module name
    * `--out` - (required) the output path for the generated TypeScript file
    * `--client-import` - the import specifier for the client package
      (default: `"@elixir-ts-rpc/client"`)

  """

  use Mix.Task

  @shortdoc "Generate a TypeScript client from an RPC router"

  @impl Mix.Task
  def run(["--help"]), do: Mix.Task.run("help", ["rpc.gen.ts"])
  def run(["-h"]), do: Mix.Task.run("help", ["rpc.gen.ts"])

  def run(args) do
    Mix.Task.run("compile")

    {opts, _} =
      try do
        OptionParser.parse!(args,
          strict: [router: :string, out: :string, client_import: :string]
        )
      rescue
        e in OptionParser.ParseError ->
          Mix.raise(
            "#{e.message}\n\nUsage: mix rpc.gen.ts --router MyApp.Router --out path/to/rpc.gen.ts"
          )
      end

    router_name = opts[:router] || raise Mix.Error, message: "missing required option --router"
    out_path = opts[:out] || raise Mix.Error, message: "missing required option --out"

    router_mod = parse_module!(router_name)

    unless function_exported?(router_mod, :__procedures__, 0) do
      Mix.raise(
        "Module #{inspect(router_mod)} is not an RPC router. It must `use RpcElixir.Router`"
      )
    end

    procedures = router_mod.__procedures__()
    codegen_opts = Keyword.take(opts, [:client_import]) ++ [out: out_path]
    source = RpcElixir.Codegen.generate(router_mod, codegen_opts)

    out_path |> Path.dirname() |> File.mkdir_p!()
    File.write!(out_path, source)

    Mix.shell().info("Wrote #{length(procedures)} procedures to #{out_path}")
  end

  defp parse_module!(name) do
    mod = Module.concat([name])

    case Code.ensure_compiled(mod) do
      {:module, _} ->
        mod

      {:error, reason} ->
        raise Mix.Error,
          message: "could not load router module #{inspect(mod)}: #{reason}"
    end
  end
end
