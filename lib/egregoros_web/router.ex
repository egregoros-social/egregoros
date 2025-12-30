defmodule EgregorosWeb.Router do
  use EgregorosWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug EgregorosWeb.Plugs.FetchCurrentUser
    plug :put_root_layout, html: {EgregorosWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :browser_api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug EgregorosWeb.Plugs.FetchCurrentUser
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :admin do
    plug EgregorosWeb.Plugs.RequireAdmin
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_auth do
    plug EgregorosWeb.Plugs.RequireAuth
  end

  pipeline :api_optional_auth do
    plug EgregorosWeb.Plugs.FetchOptionalAuth
  end

  pipeline :oauth_read do
    plug EgregorosWeb.Plugs.RequireScopes, ["read"]
  end

  pipeline :oauth_write do
    plug EgregorosWeb.Plugs.RequireScopes, ["write"]
  end

  pipeline :oauth_follow do
    plug EgregorosWeb.Plugs.RequireScopes, ["follow"]
  end

  scope "/", EgregorosWeb do
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
    post "/logout", RegistrationController, :logout

    live "/settings/privacy", PrivacyLive
    live "/", TimelineLive
    live "/search", SearchLive
    live "/tags/:tag", TagLive
    live "/notifications", NotificationsLive
    live "/messages", MessagesLive
    live "/bookmarks", BookmarksLive, :bookmarks
    live "/favourites", BookmarksLive, :favourites
    live "/@:nickname", ProfileLive
    live "/@:nickname/followers", RelationshipsLive, :followers
    live "/@:nickname/following", RelationshipsLive, :following
    live "/@:nickname/:uuid", StatusLive
  end

  scope "/", EgregorosWeb do
    pipe_through [:browser, :admin]

    get "/admin", AdminController, :index
    post "/admin/relays", AdminController, :create_relay
  end

  scope "/", EgregorosWeb do
    pipe_through :browser_api

    get "/settings/e2ee", E2EEController, :show
    post "/settings/e2ee/passkey", E2EEController, :enable_passkey
    post "/passkeys/registration/options", PasskeysController, :registration_options
    post "/passkeys/registration/finish", PasskeysController, :registration_finish
    post "/passkeys/authentication/options", PasskeysController, :authentication_options
    post "/passkeys/authentication/finish", PasskeysController, :authentication_finish
  end

  scope "/", EgregorosWeb do
    pipe_through :api

    post "/oauth/token", OAuthController, :token
    post "/oauth/revoke", OAuthController, :revoke
    get "/users/:nickname", ActorController, :show
    post "/users/:nickname/inbox", InboxController, :inbox
    get "/users/:nickname/outbox", OutboxController, :outbox
    get "/users/:nickname/followers", FollowCollectionController, :followers
    get "/users/:nickname/following", FollowCollectionController, :following
    get "/objects/:uuid", ObjectController, :show
    get "/poco", PocoController, :index
    get "/.well-known/webfinger", WebFingerController, :webfinger
    get "/.well-known/nodeinfo", NodeinfoController, :nodeinfo_index
    get "/nodeinfo/2.0.json", NodeinfoController, :nodeinfo
    get "/nodeinfo/2.0", NodeinfoController, :nodeinfo
  end

  scope "/api/v1", EgregorosWeb.MastodonAPI do
    pipe_through [:api, :api_auth]

    get "/followed_tags", EmptyListController, :index
    get "/push/subscription", PushSubscriptionController, :show
    post "/push/subscription", PushSubscriptionController, :create
    put "/push/subscription", PushSubscriptionController, :update
    delete "/push/subscription", PushSubscriptionController, :delete
  end

  scope "/api/v1", EgregorosWeb.MastodonAPI do
    pipe_through [:api, :api_auth, :oauth_write]

    patch "/accounts/update_credentials", AccountsController, :update_credentials
    post "/accounts/:id/block", AccountsController, :block
    post "/accounts/:id/unblock", AccountsController, :unblock
    post "/accounts/:id/mute", AccountsController, :mute
    post "/accounts/:id/unmute", AccountsController, :unmute
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

  scope "/api/v1", EgregorosWeb.MastodonAPI do
    pipe_through [:api, :api_auth, :oauth_follow]

    post "/follows", FollowsController, :create
    post "/accounts/:id/follow", AccountsController, :follow
    post "/accounts/:id/unfollow", AccountsController, :unfollow
    post "/follow_requests/:id/authorize", FollowRequestsController, :authorize
    post "/follow_requests/:id/reject", FollowRequestsController, :reject
  end

  scope "/api/v1", EgregorosWeb.MastodonAPI do
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
    get "/blocks", BlocksController, :index
    get "/mutes", MutesController, :index
    get "/follow_requests", FollowRequestsController, :index
    get "/markers", MarkersController, :index
    get "/statuses/:id/favourited_by", StatusesController, :favourited_by
    get "/statuses/:id/reblogged_by", StatusesController, :reblogged_by
  end

  scope "/api/v1", EgregorosWeb.MastodonAPI do
    pipe_through :api

    post "/apps", AppsController, :create
    get "/streaming", StreamingController, :index
    get "/streaming/:stream", StreamingController, :index
    get "/streaming/:stream/:scope", StreamingController, :index
    get "/instance", InstanceController, :show
    get "/instance/peers", InstanceController, :peers
    get "/custom_emojis", CustomEmojisController, :index
    get "/trends", TrendsController, :index
    get "/trends/tags", TrendsController, :tags
    get "/trends/links", TrendsController, :links
    get "/trends/statuses", TrendsController, :statuses
    get "/timelines/public", TimelinesController, :public
    get "/directory", EmptyListController, :index
    get "/accounts/lookup", AccountsController, :lookup
    get "/accounts/:id", AccountsController, :show
    get "/accounts/:id/statuses", AccountsController, :statuses
    get "/accounts/:id/followers", AccountsController, :followers
    get "/accounts/:id/following", AccountsController, :following
  end

  scope "/api/v1", EgregorosWeb.MastodonAPI do
    pipe_through [:api, :api_optional_auth]

    get "/statuses/:id", StatusesController, :show
    get "/statuses/:id/context", StatusesController, :context
  end

  scope "/api/v2", EgregorosWeb.MastodonAPI do
    pipe_through :api

    get "/instance", InstanceController, :show_v2
    get "/search", SearchController, :index
  end

  scope "/api/v2", EgregorosWeb.MastodonAPI do
    pipe_through [:api, :api_auth, :oauth_write]

    post "/media", MediaController, :create
  end

  scope "/api/v1/pleroma", EgregorosWeb.PleromaAPI do
    pipe_through [:api, :api_auth, :oauth_write]

    put "/statuses/:id/reactions/:emoji", EmojiReactionController, :create
    delete "/statuses/:id/reactions/:emoji", EmojiReactionController, :delete
  end

  scope "/api/v1/pleroma", EgregorosWeb.PleromaAPI do
    pipe_through [:api, :api_auth, :oauth_read]

    get "/statuses/:id/reactions", EmojiReactionController, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", EgregorosWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:egregoros, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: EgregorosWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
