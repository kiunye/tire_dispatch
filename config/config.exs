# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :tire_dispatch, :scopes,
  user: [
    default: true,
    module: TireDispatch.Users.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: TireDispatch.UsersFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :tire_dispatch,
  ecto_repos: [TireDispatch.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :tire_dispatch, TireDispatchWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: TireDispatchWeb.ErrorHTML, json: TireDispatchWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TireDispatch.PubSub,
  live_view: [signing_salt: "Xqcx7vXA"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :tire_dispatch, TireDispatch.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  tire_dispatch: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  tire_dispatch: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :request_id,
    :job_id,
    :transaction_id,
    :payout_id,
    :provider_id,
    :driver_id,
    :session_id,
    :amount_cents,
    :type,
    :status,
    :external_transaction_id,
    :payment_method,
    :reason,
    :error,
    :original_transaction_id,
    :refund_transaction_id,
    :refund_id,
    :mpesa_transaction_id,
    :conversation_id,
    :charge_id,
    :destination,
    :amount
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Oban configuration
config :tire_dispatch, Oban,
  engine: Oban.Engines.Basic,
  queues: [
    default: 10,
    payments: 20,
    notifications: 15,
    analytics: 5
  ],
  repo: TireDispatch.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Repeater, mode: :global}
  ]

# Platform commission percentage
config :tire_dispatch, :platform_commission_percent, 15

# Google Maps API configuration
config :tire_dispatch, :google_maps_api_key, System.get_env("GOOGLE_MAPS_API_KEY")

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
