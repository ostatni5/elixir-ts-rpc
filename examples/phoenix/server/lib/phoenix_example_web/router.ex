defmodule PhoenixExampleWeb.Router do
  use PhoenixExampleWeb, :router

  import PhoenixExampleWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PhoenixExampleWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # The RPC route reuses Phoenix's own auth (`fetch_current_scope_for_user`) and
  # Phoenix's own CSRF protection (`protect_from_forgery`). Both run before the
  # forwarded `RpcElixir.Plug`, so RPC procedures inherit the same logged-in
  # scope as the rest of the app and the same CSRF guard as any Phoenix POST.
  pipeline :rpc do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :fetch_current_scope_for_user
  end

  scope "/", PhoenixExampleWeb do
    pipe_through :browser

    # Serve the React SPA shell. Going through `:browser` gives it the standard
    # `<meta name="csrf-token">` (via the layout) and the current scope.
    get "/", SpaController, :index
  end

  scope "/" do
    pipe_through :rpc

    # `path_prefix: "/rpc"` matches the mount path; `RpcElixir.Plug` strips it
    # from `conn.request_path` to derive the procedure name. CSRF is Phoenix's
    # job here, so the plug's own content-type CSRF defense is turned off.
    forward "/rpc", RpcElixir.Plug,
      router: PhoenixExampleWeb.RpcRouter,
      path_prefix: "/rpc",
      ctx_builder: &PhoenixExampleWeb.Rpc.Context.build/1,
      require_content_type: false
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:phoenix_example, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PhoenixExampleWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", PhoenixExampleWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{PhoenixExampleWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", PhoenixExampleWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{PhoenixExampleWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
