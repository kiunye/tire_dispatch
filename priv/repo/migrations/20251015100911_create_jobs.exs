defmodule TireDispatch.Repo.Migrations.CreateJobs do
  use Ecto.Migration

  def change do
    # Enable PostGIS extension
    execute("CREATE EXTENSION IF NOT EXISTS postgis", "DROP EXTENSION IF EXISTS postgis")

    create table(:jobs) do
      add :service_type, :string, null: false
      add :status, :string, null: false, default: "open"
      add :urgency_tier, :string, null: false
      add :vehicle_type, :string, null: false

      # PostGIS geometry fields for locations
      add :driver_location, :geometry, null: false
      add :provider_location, :geometry

      # Pricing fields (stored as cents)
      add :estimated_price_cents, :integer, null: false
      add :final_price_cents, :integer

      # Additional fields
      add :issue_notes, :text
      add :photos, {:array, :string}, default: []
      add :before_photo_url, :string
      add :after_photo_url, :string
      add :cancellation_reason, :text
      add :completed_at, :utc_datetime_usec

      # Foreign keys
      add :driver_id, references(:users, on_delete: :nilify_all), null: false
      add :provider_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    # Indexes
    create index(:jobs, [:status])
    create index(:jobs, [:driver_id])
    create index(:jobs, [:provider_id])
    create index(:jobs, [:completed_at])

    # PostGIS GIST index on driver_location for fast geographic queries
    create index(:jobs, [:driver_location], using: "GIST")
  end
end
