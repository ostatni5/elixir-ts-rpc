defmodule Mix.Tasks.Compile.ElixirTsRpc do
  @moduledoc """
  Mix compiler that regenerates the TypeScript client after Elixir recompiles.

  Configure in your project's `config/config.exs`:

      config :elixir_ts_rpc,
        router: MyApp.Router,
        out: Path.expand("../client/src/rpc.gen.ts", __DIR__)

  And append to the compilers list in `mix.exs`:

      compilers: Mix.compilers() ++ [:elixir_ts_rpc]

  ## Build artifacts

  The generated `.ts` file is tracked as a build artifact via `manifests/0`.
  Running `mix clean` removes it along with the standard BEAM artifacts.
  """

  use Mix.Task.Compiler

  @impl true
  def run(_args) do
    with {:ok, router} <- fetch_config(:router),
         {:ok, out} <- fetch_config(:out) do
      regenerate(router, out)
    else
      {:error, :not_configured} -> {:noop, []}
    end
  end

  @impl true
  def manifests do
    case Application.get_env(:elixir_ts_rpc, :out) do
      nil -> []
      out -> [out]
    end
  end

  @impl true
  def clean do
    Enum.each(manifests(), fn path ->
      if File.exists?(path), do: File.rm!(path)
    end)
  end

  defp fetch_config(key) do
    case Application.get_env(:elixir_ts_rpc, key) do
      nil -> {:error, :not_configured}
      value -> {:ok, value}
    end
  end

  defp regenerate(router, out) do
    # Rely on the normal Elixir compiler to produce fresh BEAM files.
    # Code.ensure_loaded/1 is sufficient, we do NOT manually purge or
    # load_file here, which would race the parallel compiler and could purge
    # a module currently held by another process.
    case Code.ensure_loaded(router) do
      {:module, _} ->
        {write_if_changed(router, out), []}

      {:error, _} ->
        {:noop, []}
    end
  end

  defp write_if_changed(router, out) do
    new_content = RpcElixir.Codegen.generate(router, out: out)
    existing = if File.exists?(out), do: File.read!(out), else: :none

    if existing == new_content do
      :noop
    else
      File.mkdir_p!(Path.dirname(out))
      File.write!(out, new_content)
      Mix.shell().info("[elixir_ts_rpc] regenerated #{out}")
      :ok
    end
  end
end
