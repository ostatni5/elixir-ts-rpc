defmodule BasicServer.AuthPlug do
  @moduledoc """
  Plain HTTP endpoints for session lifecycle: `POST /auth/login` and
  `POST /auth/logout`.

  These live outside the RPC router because they need to mutate the session
  cookie on the response, something the RPC handler contract does not allow
  (handlers return values, they do not write headers/cookies).

  `auth.me` remains an RPC procedure: it only *reads* the session, so it fits
  cleanly into the typed RPC manifest.

  This plug must be mounted BEFORE any plug that consumes the request body
  (e.g. `Plug.Parsers`). If the body has already been read, `read_body/1`
  returns an empty string and login is rejected with 400.

  Non-matching requests fall through untouched so subsequent plugs can run.
  """

  import Plug.Conn

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{method: "POST", request_path: "/auth/login"} = conn, _opts) do
    with {:ok, body, conn} when body != "" <- read_body(conn),
         {:ok, %{"username" => username, "password" => password}} <- JSON.decode(body),
         {:ok, user} <- BasicServer.Users.authenticate(username, password) do
      conn
      |> put_session(:user_id, user.id)
      |> json_resp(200, %{ok: %{id: user.id, email: user.email, role: user.role}})
      |> halt()
    else
      {:error, :invalid} ->
        conn
        |> json_resp(401, %{error: %{code: "unauthorized", message: "invalid credentials"}})
        |> halt()

      _ ->
        conn
        |> json_resp(400, %{error: %{code: "bad_request", message: "invalid request body"}})
        |> halt()
    end
  end

  def call(%Plug.Conn{method: "POST", request_path: "/auth/logout"} = conn, _opts) do
    conn
    |> clear_session()
    |> json_resp(200, %{ok: %{ok: true}})
    |> halt()
  end

  def call(conn, _opts), do: conn

  defp json_resp(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(body))
  end
end
