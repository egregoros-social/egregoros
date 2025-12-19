defmodule PleromaReduxWeb.Router do
  use PleromaReduxWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug PleromaReduxWeb.Plugs.FetchCurrentUser
    plug :put_root_layout, html: {PleromaReduxWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_auth do
    plug PleromaReduxWeb.Plugs.RequireAuth
  end

  scope "/", PleromaReduxWeb do
    pipe_through :browser

    get "/register", RegistrationController, :new
    post "/register", RegistrationController, :create
    get "/login", SessionController, :new
    post "/login", SessionController, :create
    get "/logout", RegistrationController, :logout

    live "/", TimelineLive
  end

  scope "/", PleromaReduxWeb do
    pipe_through :api

    get "/users/:nickname", ActorController, :show
    post "/users/:nickname/inbox", InboxController, :inbox
    get "/users/:nickname/outbox", OutboxController, :outbox
    get "/users/:nickname/followers", FollowCollectionController, :followers
    get "/users/:nickname/following", FollowCollectionController, :following
    get "/objects/:uuid", ObjectController, :show
    get "/.well-known/webfinger", WebFingerController, :webfinger
    get "/.well-known/nodeinfo", NodeinfoController, :nodeinfo_index
    get "/nodeinfo/2.0.json", NodeinfoController, :nodeinfo
  end

  scope "/api/v1", PleromaReduxWeb.MastodonAPI do
    pipe_through [:api, :api_auth]

    get "/accounts/verify_credentials", AccountsController, :verify_credentials
    get "/timelines/home", TimelinesController, :home
    post "/accounts/:id/follow", AccountsController, :follow
    post "/accounts/:id/unfollow", AccountsController, :unfollow
    post "/statuses", StatusesController, :create
    post "/statuses/:id/favourite", StatusesController, :favourite
    post "/statuses/:id/unfavourite", StatusesController, :unfavourite
    post "/statuses/:id/reblog", StatusesController, :reblog
    post "/statuses/:id/unreblog", StatusesController, :unreblog
  end

  scope "/api/v1", PleromaReduxWeb.MastodonAPI do
    pipe_through :api

    get "/timelines/public", TimelinesController, :public
    get "/statuses/:id", StatusesController, :show
    get "/accounts/:id", AccountsController, :show
  end

  scope "/api/v1/pleroma", PleromaReduxWeb.PleromaAPI do
    pipe_through [:api, :api_auth]

    put "/statuses/:id/reactions/:emoji", EmojiReactionController, :create
    delete "/statuses/:id/reactions/:emoji", EmojiReactionController, :delete
  end

  # Other scopes may use custom stacks.
  # scope "/api", PleromaReduxWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:pleroma_redux, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PleromaReduxWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
