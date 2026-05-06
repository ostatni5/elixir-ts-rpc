defmodule RpcElixir.MixProject do
  use Mix.Project

  # Test-only: enables set-theoretic inference for our own fixtures so
  # `RpcElixir.Types.FromInferred` tests have signatures to read. Downstream
  # users who want the FromInferred backend must enable this in their own
  # `mix.exs`, compiler options don't propagate from a dependency.
  if Mix.env() == :test do
    Code.compiler_options(infer_signatures: true)
  end

  @version "0.0.1"
  @source_url "https://github.com/ostatni5/elixir-ts-rpc"

  def project do
    [
      app: :elixir_ts_rpc,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      dialyzer: dialyzer(),
      description:
        "Foundation for typed RPC procedures with TypeScript-compatible type resolution from @spec",
      package: package(),
      docs: docs(),
      source_url: @source_url
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # PLT lives under _build so CI can cache it per OTP/Elixir build.
  defp dialyzer do
    [
      plt_local_path: "_build/#{Mix.env()}/plt",
      plt_core_path: "_build/#{Mix.env()}/plt",
      # :mix is needed so the Mix.Task / Mix.Task.Compiler callbacks and the
      # Mix.* helper calls in our generator tasks are known to dialyzer.
      plt_add_apps: [:mix],
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  end

  defp deps do
    [
      {:plug, "~> 1.16"},
      # Optional: only needed by the `rpc.gen.ts.watch` task. Consumers who use
      # watch mode must add `:file_system` to their own deps.
      {:file_system, "~> 1.0", optional: true},
      {:ecto, "~> 3.13", only: :test},
      {:ex_json_schema, "~> 0.10", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  # Publish from this directory: `cd apps/rpc_elixir && mix hex.publish`
  defp package do
    [
      name: "elixir_ts_rpc",
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/ostatni5/elixir-ts-rpc",
        "Guide" => "https://ostatni5.github.io/elixir-ts-rpc/"
      },
      files: ["lib", "mix.exs", "README.md", "LICENSE", "CHANGELOG.md", "docs"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", "docs/supported-types.md"],
      source_url: @source_url,
      source_ref: @version,
      # These live in Elixir core but are `@moduledoc false`, so ExDoc can't
      # link to them. They're still the clearest way to name the APIs we use.
      skip_code_autolink_to: [
        "Code.Typespec",
        "Code.Typespec.fetch_specs/1",
        "Code.Typespec.spec_to_quoted/2",
        "Module.Types.Descr"
      ]
    ]
  end
end
