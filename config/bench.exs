import Config

# Configure your database (recommended: keep this isolated from dev/prod)
config :pleroma_redux, PleromaRedux.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "pleroma_redux_bench",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 20

# We don't run an HTTP server during benchmarks; the suite runs directly against the DB.
config :pleroma_redux, PleromaReduxWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4003],
  secret_key_base: "tB7hBkFAvy/E0h6QnykVSJfIEY3o9b3tTpnJ+vL+E6mkL4Sji4d6bt/smQGJPSuQ",
  server: false

# Faster password hashing for bench data generation.
config :pleroma_redux, :password_iterations, 1_000

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

# Keep logs readable for interactive bench runs.
config :logger, level: :info
