#!/usr/bin/env bash
# Builds the playground into dist/. Used by humans and by
# .github/workflows/deploy-playground.yml, so the two cannot drift.
#
# Pass --production to drop sourcemaps and minify (81MB -> 34MB).
set -euo pipefail
cd "$(dirname "$0")"

production=""
[[ "${1:-}" == "--production" ]] && production=1

mix deps.get
# start_module has to be passed here: Popcorn.cook/1 does not read it from config.exs.
mix run -e 'Popcorn.cook(start_module: Playground.Server)'

cd assets
if [[ -n "${CI:-}" ]]; then npm ci; else npm install; fi
if [[ -n "$production" ]]; then NODE_ENV=production node build.mjs; else node build.mjs; fi

cd ..
echo "built dist/ ($(du -sh dist | cut -f1))"
