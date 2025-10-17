import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :tire_dispatch, TireDispatch.Repo,
  username: System.get_env("POSTGRES_USER") || "chris",
  password: System.get_env("POSTGRES_PASSWORD") || "ynbt2qra",
  hostname: System.get_env("POSTGRES_HOST") || "localhost",
  database: "tire_dispatch_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Stripe configuration for testing
config :stripity_stripe,
  api_key: "sk_test_fake_key_for_testing",
  public_key: "pk_test_fake_key_for_testing",
  webhook_secret: "whsec_test_fake_webhook_secret"
