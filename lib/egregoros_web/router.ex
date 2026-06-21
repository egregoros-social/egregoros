defmodule EgregorosWeb.Router do
  use EgregorosWeb, :router

  import Oban.Web.Router
  import Phoenix.LiveDashboard.Router

  pipeline :health do
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug EgregorosWeb.Plugs.FetchCurrentUser
    plug :put_root_layout, html: {EgregorosWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :browser_root do
    plug :accepts, ["html", "json"]
    plug EgregorosWeb.Plugs.ServeInstanceActor
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
    pipe_through :health

    get "/health", HealthController, :show
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
    live "/search", SearchLive
    live "/explore", ExploreLive
    live "/tags/:tag", TagLive
    live "/notifications", NotificationsLive
    live "/messages", MessagesLive
    live "/bookmarks", BookmarksLive, :bookmarks
    live "/favourites", BookmarksLive, :favourites
    live "/@:nickname", ProfileLive
    live "/@:nickname/followers", RelationshipsLive, :followers
    live "/@:nickname/following", RelationshipsLive, :following
    live "/@:nickname/badges", BadgesLive, :index
    live "/@:nickname/badges/:id", BadgesLive, :show
    live "/@:nickname/:uuid", StatusLive
  end

  scope "/", EgregorosWeb do
    pipe_through :browser_root

    live "/", TimelineLive
  end

  scope "/", EgregorosWeb do
    pipe_through [:browser, :admin]

    get "/admin", AdminController, :index
    post "/admin/registrations", AdminController, :update_registrations
    post "/admin/badges/issue", AdminController, :issue_badge
    post "/admin/badges/:id", AdminController, :update_badge_definition
    post "/admin/badges/offers/:id/rescind", AdminController, :rescind_offer
    post "/admin/relays", AdminController, :create_relay
    delete "/admin/relays/:id", AdminController, :delete_relay
  end

  scope "/admin" do
    pipe_through [:browser, :admin]

    oban_dashboard("/oban", oban_name: Oban)
    live_dashboard "/dashboard", metrics: EgregorosWeb.Telemetry, ecto_repos: [Egregoros.Repo]
  end

  scope "/", EgregorosWeb do
    pipe_through :browser_api

    get "/settings/e2ee", E2EEController, :show
    post "/settings/e2ee/mnemonic", E2EEController, :enable_mnemonic
    post "/settings/e2ee/actor_key", E2EEController, :actor_key
    post "/passkeys/registration/options", PasskeysController, :registration_options
    post "/passkeys/registration/finish", PasskeysController, :registration_finish
    post "/passkeys/authentication/options", PasskeysController, :authentication_options
    post "/passkeys/authentication/finish", PasskeysController, :authentication_finish
  end

  scope "/", EgregorosWeb do
    pipe_through :api

    post "/oauth/token", OAuthController, :token
    post "/oauth/revoke", OAuthController, :revoke
    get "/api/pleroma/frontend_configurations", PleromaFrontendConfigurationsController, :index
    get "/api/pleroma/emoji.json", PleromaEmojiController, :index
    post "/inbox", InstanceInboxController, :inbox
    get "/outbox", InstanceOutboxController, :outbox
    get "/followers", InstanceFollowCollectionController, :followers
    get "/following", InstanceFollowCollectionController, :following
    get "/users/:nickname", ActorController, :show
    post "/users/:nickname/inbox", InboxController, :inbox
    get "/users/:nickname/outbox", OutboxController, :outbox
    get "/users/:nickname/followers", FollowCollectionController, :followers
    get "/users/:nickname/following", FollowCollectionController, :following
    get "/objects/:uuid", ObjectController, :show
    get "/badges/:id", BadgeDefinitionController, :show
    get "/activities/:uuid", ActivityController, :show
    get "/activities/:type/:uuid", ActivityController, :show_typed
    get "/poco", PocoController, :index
    get "/.well-known/webfinger", WebFingerController, :webfinger
    get "/.well-known/did.json", DidController, :show
    get "/.well-known/nodeinfo", NodeinfoController, :nodeinfo_index
    get "/nodeinfo/2.0.json", NodeinfoController, :nodeinfo
    get "/nodeinfo/2.1.json", NodeinfoController, :nodeinfo_2_1
    get "/nodeinfo/2.0", NodeinfoController, :nodeinfo
  end

  scope "/api/v1", EgregorosWeb.MastodonAPI do
    pipe_through [:api, :api_auth]

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
    put "/statuses/:id", StatusesController, :update
    patch "/statuses/:id", StatusesController, :update
    delete "/statuses/:id", StatusesController, :delete
    post "/statuses/:id/favourite", StatusesController, :favourite
    post "/statuses/:id/unfavourite", StatusesController, :unfavourite
    post "/statuses/:id/bookmark", StatusesController, :bookmark
    post "/statuses/:id/unbookmark", StatusesController, :unbookmark
    post "/statuses/:id/reblog", StatusesController, :reblog
    post "/statuses/:id/unreblog", StatusesController, :unreblog
    post "/notifications/clear", NotificationsController, :clear
    post "/notifications/:id/dismiss", NotificationsController, :dismiss
    post "/polls/:id/votes", PollsController, :vote
    put "/scheduled_statuses/:id", ScheduledStatusesController, :update
    delete "/scheduled_statuses/:id", ScheduledStatusesController, :delete
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
    get "/accounts/search", AccountsController, :search
    get "/accounts/relationships", AccountsController, :relationships
    get "/timelines/home", TimelinesController, :home
    get "/notifications", NotificationsController, :index
    get "/scheduled_statuses", ScheduledStatusesController, :index
    get "/scheduled_statuses/:id", ScheduledStatusesController, :show
    get "/conversations", ConversationsController, :index
    get "/preferences", PreferencesController, :show
    get "/filters", EmptyListController, :index
    get "/lists", EmptyListController, :index
    get "/bookmarks", BookmarksController, :index
    get "/favourites", FavouritesController, :index
    get "/blocks", BlocksController, :index
    get "/mutes", MutesController, :index
    get "/followed_tags", FollowedTagsController, :index
    get "/suggestions", SuggestionsController, :index
    get "/follow_requests", FollowRequestsController, :index
    get "/markers", MarkersController, :index
    get "/statuses/:id/favourited_by", StatusesController, :favourited_by
    get "/statuses/:id/reblogged_by", StatusesController, :reblogged_by
    get "/statuses/:id/source", StatusesController, :source
  end

  scope "/api/v1", EgregorosWeb.MastodonAPI do
    pipe_through :api

    post "/apps", AppsController, :create
    get "/announcements", AnnouncementsController, :index
    post "/announcements/:id/dismiss", AnnouncementsController, :dismiss
    get "/streaming", StreamingController, :index
    get "/streaming/:stream", StreamingController, :index
    get "/streaming/:stream/:scope", StreamingController, :index
    get "/instance", InstanceController, :show
    get "/instance/activity", InstanceController, :activity
    get "/instance/rules", InstanceController, :rules
    get "/instance/extended_description", InstanceController, :extended_description
    get "/instance/privacy_policy", InstanceController, :privacy_policy
    get "/instance/terms_of_service", InstanceController, :terms_of_service
    get "/instance/languages", InstanceController, :languages
    get "/instance/translation_languages", InstanceController, :translation_languages
    get "/instance/domain_blocks", InstanceController, :domain_blocks
    get "/instance/peers", InstanceController, :peers
    get "/custom_emojis", CustomEmojisController, :index
    get "/trends", TrendsController, :index
    get "/trends/tags", TrendsController, :tags
    get "/trends/links", TrendsController, :links
    get "/trends/statuses", TrendsController, :statuses
    get "/timelines/public", TimelinesController, :public
    get "/timelines/tag/:hashtag", TimelinesController, :tag
    get "/accounts/lookup", AccountsController, :lookup
    get "/accounts/:id", AccountsController, :show
    get "/accounts/:id/followers", AccountsController, :followers
    get "/accounts/:id/following", AccountsController, :following
  end

  scope "/api/v1", EgregorosWeb.MastodonAPI do
    pipe_through [:api, :api_optional_auth]

    get "/tags/:name", TagsController, :show
    get "/directory", DirectoryController, :index
    get "/accounts/:id/statuses", AccountsController, :statuses
    get "/statuses/:id", StatusesController, :show
    get "/statuses/:id/context", StatusesController, :context
    get "/polls/:id", PollsController, :show
  end

  scope "/api/v2", EgregorosWeb.MastodonAPI do
    pipe_through :api

    get "/instance", InstanceController, :show_v2
  end

  scope "/api/v2", EgregorosWeb.MastodonAPI do
    pipe_through [:api, :api_optional_auth]

    get "/search", SearchController, :index
  end

  scope "/api/v2", EgregorosWeb.MastodonAPI do
    pipe_through [:api, :api_auth, :oauth_write]

    post "/media", MediaController, :create
  end

  scope "/api/v1/pleroma", EgregorosWeb.PleromaAPI do
    pipe_through [:api, :api_auth]

    post "/notifications/read", NotificationsController, :read
  end

  scope "/api/v1/pleroma", EgregorosWeb.PleromaAPI do
    pipe_through [:api, :api_optional_auth]

    get "/emoji", EmojiController, :index
    get "/accounts/:id/favourites", AccountsController, :favourites
    get "/accounts/:id/scrobbles", AccountsController, :scrobbles
  end

  scope "/api/v1/pleroma", EgregorosWeb.PleromaAPI do
    pipe_through [:api, :api_auth, :oauth_write]

    post "/badges/issue", BadgesController, :issue
    post "/offers/:id/accept", OffersController, :accept
    post "/offers/:id/reject", OffersController, :reject
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

  # Enable Swoosh mailbox preview in development.
  # LiveDashboard is available at /admin/dashboard.
  if Application.compile_env(:egregoros, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
