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

  pipeline :oauth_read do
    plug PleromaReduxWeb.Plugs.RequireScopes, ["read"]
  end

  pipeline :oauth_write do
    plug PleromaReduxWeb.Plugs.RequireScopes, ["write"]
  end

  pipeline :oauth_follow do
    plug PleromaReduxWeb.Plugs.RequireScopes, ["follow"]
  end

  scope "/", PleromaReduxWeb do
    pipe_through :browser

    get "/register", RegistrationController, :new
    post "/register", RegistrationController, :create
    get "/login", SessionController, :new
    post "/login", SessionController, :create
    get "/oauth/authorize", OAuthController, :authorize
    post "/oauth/authorize", OAuthController, :approve
    get "/settings", SettingsController, :edit
    post "/settings/profile", SettingsController, :update_profile
    post "/settings/account", SettingsController, :update_account
    post "/settings/password", SettingsController, :update_password
    get "/logout", RegistrationController, :logout

    live "/", TimelineLive
    live "/tags/:tag", TagLive
    live "/notifications", NotificationsLive
    live "/@:nickname", ProfileLive
    live "/@:nickname/followers", RelationshipsLive, :followers
    live "/@:nickname/following", RelationshipsLive, :following
    live "/@:nickname/:uuid", StatusLive
  end

  scope "/", PleromaReduxWeb do
    pipe_through :api

    post "/oauth/token", OAuthController, :token
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
    pipe_through [:api, :api_auth, :oauth_write]

    patch "/accounts/update_credentials", AccountsController, :update_credentials
    post "/markers", MarkersController, :create
    post "/media", MediaController, :create
    put "/media/:id", MediaController, :update
    post "/statuses", StatusesController, :create
    delete "/statuses/:id", StatusesController, :delete
    post "/statuses/:id/favourite", StatusesController, :favourite
    post "/statuses/:id/unfavourite", StatusesController, :unfavourite
    post "/statuses/:id/reblog", StatusesController, :reblog
    post "/statuses/:id/unreblog", StatusesController, :unreblog
  end

  scope "/api/v1", PleromaReduxWeb.MastodonAPI do
    pipe_through [:api, :api_auth, :oauth_follow]

    post "/follows", FollowsController, :create
    post "/accounts/:id/follow", AccountsController, :follow
    post "/accounts/:id/unfollow", AccountsController, :unfollow
  end

  scope "/api/v1", PleromaReduxWeb.MastodonAPI do
    pipe_through [:api, :api_auth, :oauth_read]

    get "/accounts/verify_credentials", AccountsController, :verify_credentials
    get "/accounts/relationships", AccountsController, :relationships
    get "/timelines/home", TimelinesController, :home
    get "/notifications", NotificationsController, :index
    get "/preferences", PreferencesController, :show
    get "/filters", EmptyListController, :index
    get "/lists", EmptyListController, :index
    get "/bookmarks", EmptyListController, :index
    get "/favourites", EmptyListController, :index
    get "/blocks", EmptyListController, :index
    get "/mutes", EmptyListController, :index
    get "/follow_requests", EmptyListController, :index
    get "/markers", MarkersController, :index
    get "/statuses/:id/favourited_by", StatusesController, :favourited_by
    get "/statuses/:id/reblogged_by", StatusesController, :reblogged_by
  end

  scope "/api/v1", PleromaReduxWeb.MastodonAPI do
    pipe_through :api

    post "/apps", AppsController, :create
    get "/streaming", StreamingController, :index
    get "/instance", InstanceController, :show
    get "/custom_emojis", CustomEmojisController, :index
    get "/timelines/public", TimelinesController, :public
    get "/statuses/:id", StatusesController, :show
    get "/statuses/:id/context", StatusesController, :context
    get "/accounts/lookup", AccountsController, :lookup
    get "/accounts/:id", AccountsController, :show
    get "/accounts/:id/statuses", AccountsController, :statuses
    get "/accounts/:id/followers", AccountsController, :followers
    get "/accounts/:id/following", AccountsController, :following
  end

  scope "/api/v2", PleromaReduxWeb.MastodonAPI do
    pipe_through :api

    get "/instance", InstanceController, :show_v2
    get "/search", SearchController, :index
  end

  scope "/api/v2", PleromaReduxWeb.MastodonAPI do
    pipe_through [:api, :api_auth, :oauth_write]

    post "/media", MediaController, :create
  end

  scope "/api/v1/pleroma", PleromaReduxWeb.PleromaAPI do
    pipe_through [:api, :api_auth, :oauth_write]

    put "/statuses/:id/reactions/:emoji", EmojiReactionController, :create
    delete "/statuses/:id/reactions/:emoji", EmojiReactionController, :delete
  end

  scope "/api/v1/pleroma", PleromaReduxWeb.PleromaAPI do
    pipe_through [:api, :api_auth, :oauth_read]

    get "/statuses/:id/reactions", EmojiReactionController, :index
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
