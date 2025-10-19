defmodule TireDispatch.Analytics.DailyStat do
  @moduledoc """
  Schema for storing aggregated daily statistics.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "daily_stats" do
    field :date, :date
    field :total_jobs, :integer, default: 0
    field :completed_jobs, :integer, default: 0
    field :cancelled_jobs, :integer, default: 0
    field :total_revenue_cents, :integer, default: 0
    field :average_response_time_minutes, :decimal
    field :provider_utilization_percent, :decimal
    field :average_job_value_cents, :integer, default: 0

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating or updating daily stats.
  """
  def changeset(daily_stat, attrs) do
    daily_stat
    |> cast(attrs, [
      :date,
      :total_jobs,
      :completed_jobs,
      :cancelled_jobs,
      :total_revenue_cents,
      :average_response_time_minutes,
      :provider_utilization_percent,
      :average_job_value_cents
    ])
    |> validate_required([:date])
    |> validate_number(:total_jobs, greater_than_or_equal_to: 0)
    |> validate_number(:completed_jobs, greater_than_or_equal_to: 0)
    |> validate_number(:cancelled_jobs, greater_than_or_equal_to: 0)
    |> validate_number(:total_revenue_cents, greater_than_or_equal_to: 0)
    |> validate_number(:average_response_time_minutes, greater_than_or_equal_to: 0)
    |> validate_number(:provider_utilization_percent,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100
    )
    |> validate_number(:average_job_value_cents, greater_than_or_equal_to: 0)
    |> unique_constraint(:date)
  end
end
