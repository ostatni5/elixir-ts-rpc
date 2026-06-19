import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :phoenix_example, PhoenixExample.Repo,
  database: Path.expand("../phoenix_example_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :phoenix_example, PhoenixExampleWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "OSy9vdMK8LYAEsMIsFdMyVYENWKgAekCyeLjRVCglZ7VZ8Dhg5I1P9AFC5uUETwo",
  server: false

# Render the SPA shell via the dev-server asset path so tests don't depend on a
# `vite build` artifact (the shell test only asserts the HTML structure).
config :phoenix_example, :vite_dev_server, "http://localhost:5173"

# In test we don't send emails
config :phoenix_example, PhoenixExample.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
