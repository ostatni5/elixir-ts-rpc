defmodule BasicServer.RootPlug do
  @moduledoc """
  Thin wrapper that injects `secret_key_base` onto the conn before delegating
  to `BasicServer.Endpoint`. This is required for `Plug.Session` cookie signing.
  """

  @behaviour Plug

  @impl Plug
  def init(opts) do
    secret_key_base = Keyword.fetch!(opts, :secret_key_base)
    endpoint_opts = BasicServer.Endpoint.init([])
    {secret_key_base, endpoint_opts}
  end

  @impl Plug
  def call(conn, {secret_key_base, endpoint_opts}) do
    # Plug.Session requires :secret_key_base to be set on the conn struct
    # before the session plug runs. Plug.Cowboy does not set it automatically,
    # so we inject it here before delegating to the endpoint.
    conn
    |> Map.put(:secret_key_base, secret_key_base)
    |> BasicServer.Endpoint.call(endpoint_opts)
  end
end
