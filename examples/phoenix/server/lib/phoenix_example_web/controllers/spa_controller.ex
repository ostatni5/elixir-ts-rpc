defmodule PhoenixExampleWeb.SpaController do
  @moduledoc """
  Serves the React SPA's HTML shell.

  The shell is rendered by Phoenix on purpose: it carries the standard
  `<meta name="csrf-token">` tag (the same mechanism LiveView's `app.js` uses),
  which is how the SPA obtains a CSRF token to send back on RPC calls. The
  React bundle itself is built by Vite (loaded from the Vite dev server in
  development, from the hashed manifest assets in production).
  """

  use PhoenixExampleWeb, :controller

  def index(conn, _params) do
    conn
    |> put_root_layout(html: false)
    |> render(:index, layout: false)
  end
end
