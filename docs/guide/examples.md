# Examples

Two runnable, full-stack examples live in the repo. Both wire the same typed RPC
end to end, but differ in the host framework and how auth is handled.

## Basic: React/Vite SPA + Plug

A React/Vite single-page app talking to an Elixir Plug backend with
cookie-session auth, end to end.

```bash
cd examples/basic
./run.sh
# open http://localhost:5173  (alice / wonderland)
```

[Browse examples/basic →](https://github.com/ostatni5/elixir-ts-rpc/tree/main/examples/basic)

## Phoenix: typed RPC on a stock Phoenix app

The same typed RPC mounted on a stock Phoenix app. It reuses Phoenix's
`mix phx.gen.auth` authentication **and** its `protect_from_forgery` CSRF. You
write no auth code, and one CSRF mechanism covers the whole app.

[Browse examples/phoenix →](https://github.com/ostatni5/elixir-ts-rpc/tree/main/examples/phoenix)

::: info Why no live demo here
This documentation site is static and hosted on GitHub Pages, so it can't run
the Elixir backend the examples need. Clone the repo and use the commands above
to see them running locally.
:::
