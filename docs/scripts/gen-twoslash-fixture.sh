#!/usr/bin/env bash
# Regenerates the twoslash fixture: the TypeScript client the docs snippets are
# type-checked against. Run this whenever examples/basic's router or handler
# specs change. CI re-runs it and fails on a diff, so the docs cannot drift from
# what codegen actually emits.
#
# RpcElixir.Codegen.generate/1 is called WITHOUT :out on purpose. That path emits
# repo-root-relative handler links instead of absolute file:/// URIs, so no local
# path from the machine running this ever reaches the published site. The links
# are then rewritten to GitHub blob URLs, which are what a docs reader can follow.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
out="$repo_root/docs/.vitepress/twoslash/rpc.generated.ts"

cd "$repo_root/examples/basic/server"
export RPC_FIXTURE_OUT="$out"

mix compile >/dev/null

mix run --no-compile -e '
  base = "https://github.com/ostatni5/elixir-ts-rpc/blob/main/"

  header = """
  // Fixture for @shikijs/vitepress-twoslash — the client the docs snippets are
  // type-checked against. Generated from BasicServer.Router; do not edit.
  // Regenerate: bash docs/scripts/gen-twoslash-fixture.sh
  """

  body =
    BasicServer.Router
    |> RpcElixir.Codegen.generate()
    |> String.replace("](examples/", "](#{base}examples/")

  File.write!(System.fetch_env!("RPC_FIXTURE_OUT"), header <> body)
' 
