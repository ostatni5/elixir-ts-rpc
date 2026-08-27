#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
trap 'kill $(jobs -p) 2>/dev/null || true' EXIT

echo "==> Fetching Elixir deps and compiling..."
(cd server && mix deps.get && mix compile)

echo "==> Installing npm deps and generating TypeScript client..."
npm install --prefix ../.. >/dev/null
npm run rpc:gen --workspace=@examples/basic-client

echo "==> Starting Elixir server on :4001..."
(cd server && mix run --no-halt) &

echo "==> Waiting for server to accept connections..."
for i in $(seq 1 20); do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    http://localhost:4001/rpc/auth.me -X POST -d '{}' \
    -H 'Content-Type: application/json' 2>/dev/null || echo 0)
  if [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "200" ]; then
    break
  fi
  sleep 0.5
done

echo "==> Server ready at http://localhost:4001"
echo "==> Starting Vite dev server — open http://localhost:5173"
npm run dev --workspace=@examples/basic-client &

wait
