# PhoenixExample - RPC demo server

This is the Phoenix server half of the `elixir-ts-rpc` Phoenix example. Do **not**
start it in isolation with `mix setup` / `mix phx.server`. The SPA is served by a
separate Vite dev server, and the demo user must be seeded first.

See the [example README](../README.md) for the full setup: it runs `./run.sh`,
which sets up the database, seeds the demo user, boots Phoenix on `:4000`, and
starts Vite on `:5173`.
