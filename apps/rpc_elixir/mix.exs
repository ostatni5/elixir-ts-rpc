defmodule RpcElixir.MixProject do
  use Mix.Project

  # Test-only: enables set-theoretic inference for our own fixtures so
  # `RpcElixir.Types.FromInferred` tests have signatures to read. Downstream
  # users who want the FromInferred backend must enable this in their own
  # `mix.exs` — compiler options don't propagate from a dependency.
  # The option does not exist before 1.19, where passing it raises.
  if Mix.env() == :test and Version.match?(System.version(), ">= 1.19.0") do
    Code.compiler_options(infer_signatures: true)
  end

  @version "0.0.2"
  @source_url "https://github.com/ostatni5/elixir-ts-rpc"

  def project do
    [
      app: :elixir_ts_rpc,
      version: @version,
      elixir: "~> 1.17",
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
      # The mix tasks call Mix.Task and Mix.Project, which are absent from the
      # default PLT, so every call reads as `unknown_function` without this.
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
      # Optional: only needed on Elixir 1.17, which predates the built-in JSON
      # module. Consumers on 1.17 must add `:jason` to their own deps.
      {:jason, "~> 1.4", optional: true},
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
        "Guide" => "https://ostatni5.github.io/elixir-ts-rpc/",
        "Playground" => "https://elixir-ts-rpc-playground.netlify.app"
      },
      files: ["lib", "mix.exs", "README.md", "LICENSE", "CHANGELOG.md", "docs"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "docs/getting-started.md",
        "docs/plug-options.md",
        "docs/middleware.md",
        "docs/supported-types.md",
        "docs/errors.md",
        "docs/custom-types.md",
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        Guides: ~r"docs/"
      ],
      groups_for_modules: [
        "Defining procedures": [
          RpcElixir.Handler,
          RpcElixir.Router,
          RpcElixir.Middleware,
          RpcElixir.Middleware.Assign,
          RpcElixir.Context,
          RpcElixir.Resolution
        ],
        "Serving requests": [
          RpcElixir.Plug,
          RpcElixir.Dispatcher,
          RpcElixir.RpcError
        ],
        Types: [
          RpcElixir.Types,
          RpcElixir.Types.FromSpec,
          RpcElixir.CustomType,
          RpcElixir.UnixMillis,
          RpcElixir.Types.FromInferred
        ],
        Codegen: [
          RpcElixir.Codegen,
          RpcElixir.Watcher,
          Mix.Tasks.Rpc.Gen.Ts,
          Mix.Tasks.Rpc.Gen.Ts.Watch,
          Mix.Tasks.Compile.ElixirTsRpc
        ]
      ],
      source_url: @source_url,
      # No `v` prefix: releases are tagged bare (`0.0.1`), and a mismatch here
      # 404s every source link on hexdocs.
      source_ref: @version
    ]
  end
end
