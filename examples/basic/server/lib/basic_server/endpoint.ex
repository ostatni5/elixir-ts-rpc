defmodule BasicServer.Endpoint do
  @moduledoc "HTTP pipeline for the basic demo server."

  use Plug.Builder

  plug Plug.Logger

  # Salts are not secret — they are combined with secret_key_base via HKDF.
  # Only SECRET_KEY_BASE needs to be rotated for production deployments.
  plug Plug.Session,
    store: :cookie,
    key: "_basic_session",
    signing_salt: "basic_demo_signing_salt",
    encryption_salt: "basic_demo_enc_salt",
    same_site: "Lax"

  plug :fetch_session

  # Session-mutating auth endpoints (login/logout) live outside the RPC router
  # because RPC handlers cannot write to the response. `auth.me` is still RPC.
  plug BasicServer.AuthPlug

  plug RpcElixir.Plug, router: BasicServer.Router, path_prefix: "/rpc"
end
