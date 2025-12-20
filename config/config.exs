# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :pleroma_redux,
  ecto_repos: [PleromaRedux.Repo],
  generators: [timestamp_type: :utc_datetime]

config :pleroma_redux, Oban,
  repo: PleromaRedux.Repo,
  notifier: Oban.Notifiers.PG,
  queues: [
    federation_incoming: 10,
    federation_outgoing: 25
  ],
  plugins: [{Oban.Plugins.Pruner, max_age: 60 * 60 * 24}]

config :pleroma_redux, PleromaRedux.Signature, PleromaRedux.Signature.HTTP
config :pleroma_redux, PleromaRedux.Auth, PleromaRedux.Auth.BearerToken
config :pleroma_redux, PleromaRedux.AuthZ, PleromaRedux.AuthZ.OAuthScopes
config :pleroma_redux, PleromaRedux.Discovery, PleromaRedux.Discovery.DNS
config :pleroma_redux, PleromaRedux.HTTP, PleromaRedux.HTTP.Req
config :pleroma_redux, PleromaRedux.AvatarStorage, PleromaRedux.AvatarStorage.Local
config :pleroma_redux, PleromaRedux.MediaStorage, PleromaRedux.MediaStorage.Local

config :pleroma_redux, :password_iterations, 200_000

# Configure the endpoint
config :pleroma_redux, PleromaReduxWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PleromaReduxWeb.ErrorHTML, json: PleromaReduxWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: PleromaRedux.PubSub,
  live_view: [signing_salt: "o6GDDK1W"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :pleroma_redux, PleromaRedux.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  pleroma_redux: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  pleroma_redux: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :mime, :types, %{
  "application/activity+json" => ["json"],
  "application/ld+json" => ["json"],
  "audio/mp4" => ["m4a"],
  "audio/ogg" => ["ogg"],
  "audio/opus" => ["opus"]
}

config :mime, :extensions, %{
  "json" => "application/json"
}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
