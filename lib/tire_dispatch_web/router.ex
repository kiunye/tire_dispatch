defmodule TireDispatchWeb.Router do
  use TireDispatchWeb, :router

  import TireDispatchWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TireDispatchWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TireDispatchWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Webhook routes (no CSRF protection needed)
  scope "/api", TireDispatchWeb do
    pipe_through :api

    post "/webhooks/stripe", WebhookController, :stripe_webhook
    post "/mpesa/stk-callback", MPESAWebhookController, :stk_callback
    post "/mpesa/timeout", MPESAWebhookController, :timeout_callback
    post "/mpesa/result", MPESAWebhookController, :b2c_result_callback
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:tire_dispatch, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: TireDispatchWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", TireDispatchWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{TireDispatchWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", TireDispatchWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{TireDispatchWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
