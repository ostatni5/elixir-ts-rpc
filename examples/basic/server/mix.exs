defmodule BasicServer.MixProject do
  use Mix.Project

  def project do
    [
      app: :basic_server,
      version: "0.0.1",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      compilers: Mix.compilers() ++ [:elixir_ts_rpc],
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {BasicServer.Application, []}
    ]
  end

  defp deps do
    [
      {:elixir_ts_rpc, path: "../../../apps/rpc_elixir"},
      {:plug, "~> 1.16"},
      {:plug_cowboy, "~> 2.8"},
      {:file_system, "~> 1.0", only: :dev}
    ]
  end
end
