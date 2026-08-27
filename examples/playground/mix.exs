defmodule Playground.MixProject do
  use Mix.Project

  def project do
    [
      app: :playground,
      version: "0.1.0",
      elixir: "~> 1.17",
      deps: deps()
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [
      {:popcorn, "~> 0.3"},
      {:elixir_ts_rpc, path: "../../apps/rpc_elixir"},
      {:jason, "~> 1.4"}
    ]
  end
end
