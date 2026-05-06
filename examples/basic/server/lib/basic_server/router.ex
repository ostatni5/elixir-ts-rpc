defmodule BasicServer.Router do
  @moduledoc "RPC router for the basic demo."

  use RpcElixir.Router, wire_aliases: [{DateTime, RpcElixir.UnixMillis}]

  alias BasicServer.Handlers.{Auth, Users}
  alias BasicServer.Middleware.RequireUser

  procedure "auth.me", &Auth.me/2, middleware: [RequireUser]
  procedure "users.list", &Users.list/2, middleware: [RequireUser]
  procedure "users.get", &Users.get/2, middleware: [RequireUser]
  procedure "users.update", &Users.update/2, middleware: [RequireUser]
  procedure "users.delete", &Users.delete/2, middleware: [RequireUser]
end
