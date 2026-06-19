# The RPC router DSL reads best without parens; export the list so apps that
# depend on this library inherit it via `import_deps: [:elixir_ts_rpc]`.
locals_without_parens = [
  procedure: 2,
  procedure: 3,
  scope: 2,
  scope: 3,
  expose: 1,
  expose: 2
]

[
  inputs: ["mix.exs", "{lib,test}/**/*.{ex,exs}"],
  import_deps: [:plug],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
