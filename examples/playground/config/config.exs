import Config

# :crypto and :eex are pulled in transitively by :plug (plug_crypto and
# Plug.Debugger's templates). Popcorn only auto-packs non-builtin deps, so
# builtin OTP/Elixir apps have to be named here.
config :popcorn,
  out_dir: "dist/wasm",
  extra_apps: [:crypto, :eex]
