defmodule BasicServer.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    secret_key_base = Application.fetch_env!(:basic_server, :secret_key_base)

    port = String.to_integer(System.get_env("PORT") || "4001")

    children = [
      {Plug.Cowboy,
       scheme: :http,
       plug: {BasicServer.RootPlug, secret_key_base: secret_key_base},
       options: [port: port]}
    ]

    opts = [strategy: :one_for_one, name: BasicServer.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
