import Config

config :logger, level: :info

config :elixir_ts_rpc,
  router: BasicServer.Router,
  out: Path.expand("../../client/src/rpc.gen.ts", __DIR__)
