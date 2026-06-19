#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
trap 'kill $(jobs -p) 2>/dev/null || true' EXIT

echo "==> Fetching Elixir deps, setting up the database, and compiling..."
# `mix compile` runs the :elixir_ts_rpc compiler hook, which regenerates
# client/src/rpc.gen.ts. ecto.setup also seeds the demo user.
(cd server && mix deps.get && mix ecto.setup && mix compile)

echo "==> Installing npm deps..."
npm install --prefix ../.. >/dev/null

echo "==> Starting Phoenix on :4000..."
(cd server && mix phx.server) &

echo "==> Waiting for Phoenix to accept connections..."
for _ in $(seq 1 40); do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:4000/ 2>/dev/null || echo 0)
  if [ "$HTTP_CODE" = "200" ]; then
    break
  fi
  sleep 0.5
done

echo "==> Starting Vite dev server (serves the React bundle for HMR)..."
npm run dev --workspace=@examples/phoenix-client &

echo ""
echo "==> Open http://localhost:4000"
echo "==> Log in with the seeded demo user: demo@example.com / demopassword123"
echo ""

wait
