defmodule TireDispatch.Repo.Migrations.CreateProviders do
  use Ecto.Migration

  def change do
    create table(:providers) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :service_radius_km, :integer, default: 10, null: false
      add :vehicle_type, :string, null: false
      add :rating, :decimal, precision: 3, scale: 2, default: 0.0
      add :is_active, :boolean, default: true, null: false
      add :is_verified, :boolean, default: false, null: false
      add :is_premium, :boolean, default: false, null: false
      add :stripe_account_id, :string
      add :latitude, :float
      add :longitude, :float

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:providers, [:user_id])
    create index(:providers, [:stripe_account_id])

    # PostGIS spatial index on latitude and longitude
    execute(
      "CREATE INDEX providers_location_idx ON providers USING GIST (ST_MakePoint(longitude, latitude))",
      "DROP INDEX providers_location_idx"
    )
  end
end
