defmodule TireDispatch.Repo do
  use Ecto.Repo,
    otp_app: :tire_dispatch,
    adapter: Ecto.Adapters.Postgres
end
