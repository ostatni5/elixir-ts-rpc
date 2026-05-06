# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :phoenix_example, :scopes,
  user: [
    default: true,
    module: PhoenixExample.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: PhoenixExample.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :phoenix_example,
  ecto_repos: [PhoenixExample.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :phoenix_example, PhoenixExampleWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PhoenixExampleWeb.ErrorHTML, json: PhoenixExampleWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: PhoenixExample.PubSub,
  live_view: [signing_salt: "g39C68RA"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :phoenix_example, PhoenixExample.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  phoenix_example: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  phoenix_example: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# The :elixir_ts_rpc compiler hook (see mix.exs `compilers:`) regenerates the
# typed TypeScript client from the router's @specs on every `mix compile`.
config :elixir_ts_rpc,
  router: PhoenixExampleWeb.RpcRouter,
  out: Path.expand("../../client/src/rpc.gen.ts", __DIR__)

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
