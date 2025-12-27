import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :egregoros, Egregoros.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "egregoros_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :egregoros, EgregorosWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "KwKn1GsDDoRbDGP7Xmp55VIXXlRrQ8cmyst5TlSHXjzf1rwDRs6q9oiCorWwAQnq",
  server: false

# In test we don't send emails
config :egregoros, Egregoros.Mailer, adapter: Swoosh.Adapters.Test

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

config :egregoros, Egregoros.Auth, Egregoros.Auth.Mock
config :egregoros, Egregoros.Discovery, Egregoros.Discovery.Mock
config :egregoros, Egregoros.HTTP, Egregoros.HTTP.Mock
config :egregoros, Egregoros.DNS, Egregoros.DNS.Mock
config :egregoros, Egregoros.AuthZ, Egregoros.AuthZ.Mock
config :egregoros, Egregoros.AvatarStorage, Egregoros.AvatarStorage.Mock
config :egregoros, Egregoros.BannerStorage, Egregoros.BannerStorage.Mock
config :egregoros, Egregoros.MediaStorage, Egregoros.MediaStorage.Mock
config :egregoros, Egregoros.RateLimiter, Egregoros.RateLimiter.Mock

config :egregoros, :password_iterations, 1_000

config :egregoros, :req_options, plug: {Req.Test, Egregoros.HTTP.Req}

config :egregoros, Oban, testing: :manual
