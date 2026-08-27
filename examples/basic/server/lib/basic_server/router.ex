defmodule BasicServer.Router do
  @moduledoc """
  RPC router for the basic demo.

  Each handler module is exposed whole, so its public `@spec`'d functions are the
  API surface. `RequireUser` wraps every scope, which makes authentication a
  structural property of the router rather than a flag repeated per procedure.
  """

  use RpcElixir.Router, wire_aliases: [{DateTime, RpcElixir.UnixMillis}]

  alias BasicServer.Handlers.{Auth, Users}
  alias BasicServer.Middleware.RequireUser

  scope middleware: [RequireUser] do
    scope "auth" do
      expose Auth
    end

    scope "users" do
      expose Users
    end
  end
end
