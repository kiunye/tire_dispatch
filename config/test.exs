import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1
# We don't run a server during test. If one is required,
# you can enable the server option below.
config :tire_dispatch, TireDispatchWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "/sy8Djh6V+mCpMW6t93Wrw0v3wJrSiAPh1GpvE99GdvLPmINNt7N4/wu0DUxI1QF",
  server: false

# In test we don't send emails
config :tire_dispatch, TireDispatch.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# AWS S3 configuration for test (use mock or test bucket)
config :ex_aws,
  access_key_id: "test_key",
  secret_access_key: "test_secret",
  region: "us-east-1"

config :ex_aws, :s3,
  scheme: "https://",
  host: "s3.amazonaws.com",
  region: "us-east-1"

import_config "test.secret.exs"
