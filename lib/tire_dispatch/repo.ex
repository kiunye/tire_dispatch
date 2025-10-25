defmodule TireDispatch.Repo do
  use Ecto.Repo,
    otp_app: :tire_dispatch,
    adapter: Ecto.Adapters.Postgres

  def init(_type, config) do
    # Configure PostGIS types
    {:ok, Keyword.put(config, :types, TireDispatch.PostgresTypes)}
  end
end
