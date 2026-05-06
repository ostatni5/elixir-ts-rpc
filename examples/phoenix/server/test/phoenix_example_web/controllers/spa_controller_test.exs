defmodule PhoenixExampleWeb.SpaControllerTest do
  use PhoenixExampleWeb.ConnCase

  test "GET / serves the SPA shell with a CSRF token and a React root", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ ~s(<meta name="csrf-token")
    assert html =~ ~s(<div id="root">)
  end
end
