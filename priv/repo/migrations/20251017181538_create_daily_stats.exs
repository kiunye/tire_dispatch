defmodule TireDispatch.Repo.Migrations.CreateDailyStats do
  use Ecto.Migration

  def change do
    create table(:daily_stats) do
      add :date, :date, null: false
      add :total_jobs, :integer, default: 0
      add :completed_jobs, :integer, default: 0
      add :cancelled_jobs, :integer, default: 0
      add :total_revenue_cents, :bigint, default: 0
      add :average_response_time_minutes, :decimal, precision: 10, scale: 2
      add :provider_utilization_percent, :decimal, precision: 5, scale: 2
      add :average_job_value_cents, :integer, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:daily_stats, [:date])
  end
end
