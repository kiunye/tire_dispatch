import Config

# Configure your database
config :tire_dispatch, TireDispatch.Repo,
  username: "chris",
  password: "ynbt2qra",
  hostname: "localhost",
  database: "tire_dispatch_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
