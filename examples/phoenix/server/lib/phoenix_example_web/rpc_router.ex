defmodule PhoenixExampleWeb.RpcRouter do
  @moduledoc """
  RPC router for the Phoenix example.

  Each handler module is exposed whole, so its public `@spec`'d functions are the
  API surface and the router stays one line per handler.

  Every procedure lives inside a `RequireUser` scope, so authentication is a
  structural property of the router rather than a flag repeated per procedure.
  `RequireUser` authenticates against the `current_scope` that Phoenix's own auth
  populated — the RPC layer writes no auth code of its own.

  `DateTime` values serialize as epoch milliseconds on the wire (via the
  `RpcElixir.UnixMillis` alias), so `confirmed_at`/`inserted_at` arrive in the
  TypeScript client as numbers.
  """

  use RpcElixir.Router, wire_aliases: [{DateTime, RpcElixir.UnixMillis}]

  alias PhoenixExampleWeb.Rpc.Handlers.{Auth, Counter, Demo, Users}
  alias PhoenixExampleWeb.Rpc.Middleware.RequireUser

  scope middleware: [RequireUser] do
    scope "auth" do
      expose Auth
    end

    scope "users" do
      expose Users
    end

    scope "counter" do
      expose Counter
    end

    scope "demo" do
      expose Demo
    end
  end
end
