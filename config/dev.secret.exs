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

# Stripe configuration for development
# Use test keys from Stripe Dashboard
config :stripity_stripe,
  api_key: System.get_env("STRIPE_API_KEY") || "sk_test_your_test_key_here",
  public_key: System.get_env("STRIPE_PUBLIC_KEY") || "pk_test_your_test_key_here",
  webhook_secret: System.get_env("STRIPE_WEBHOOK_SECRET") || "whsec_test_your_webhook_secret_here"

# MPESA configuration for development
# Use sandbox credentials from Safaricom Daraja Portal
config :tire_dispatch, TireDispatch.Payments.MPESA,
  consumer_key: System.get_env("MPESA_CONSUMER_KEY") || "your_consumer_key",
  consumer_secret: System.get_env("MPESA_CONSUMER_SECRET") || "your_consumer_secret",
  shortcode: System.get_env("MPESA_SHORTCODE") || "174379",
  passkey: System.get_env("MPESA_PASSKEY") || "your_passkey",
  initiator_name: System.get_env("MPESA_INITIATOR_NAME") || "testapi",
  security_credential: System.get_env("MPESA_SECURITY_CREDENTIAL") || "your_security_credential",
  environment: System.get_env("MPESA_ENVIRONMENT") || "sandbox",
  callback_url: System.get_env("MPESA_CALLBACK_URL") || "http://localhost:4000/api/mpesa/stk-callback",
  timeout_url: System.get_env("MPESA_TIMEOUT_URL") || "http://localhost:4000/api/mpesa/timeout",
  result_url: System.get_env("MPESA_RESULT_URL") || "http://localhost:4000/api/mpesa/result"
