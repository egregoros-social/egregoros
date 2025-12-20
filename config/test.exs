import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :pleroma_redux, PleromaRedux.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "pleroma_redux_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :pleroma_redux, PleromaReduxWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "KwKn1GsDDoRbDGP7Xmp55VIXXlRrQ8cmyst5TlSHXjzf1rwDRs6q9oiCorWwAQnq",
  server: false

# In test we don't send emails
config :pleroma_redux, PleromaRedux.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

config :pleroma_redux, PleromaRedux.Auth, PleromaRedux.Auth.Mock
config :pleroma_redux, PleromaRedux.Discovery, PleromaRedux.Discovery.Mock
config :pleroma_redux, PleromaRedux.HTTP, PleromaRedux.HTTP.Mock
config :pleroma_redux, PleromaRedux.DNS, PleromaRedux.DNS.Mock
config :pleroma_redux, PleromaRedux.AuthZ, PleromaRedux.AuthZ.Mock
config :pleroma_redux, PleromaRedux.AvatarStorage, PleromaRedux.AvatarStorage.Mock
config :pleroma_redux, PleromaRedux.MediaStorage, PleromaRedux.MediaStorage.Mock

config :pleroma_redux, :password_iterations, 1_000

config :pleroma_redux, :req_options, plug: {Req.Test, PleromaRedux.HTTP.Req}
