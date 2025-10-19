defmodule TireDispatch.Workers.AnalyticsAggregatorWorker do
  @moduledoc """
  Oban worker that aggregates daily analytics statistics.

  Runs daily at 3 AM via Oban cron to:
  - Calculate platform-wide KPIs for the previous day
  - Store aggregated statistics in the daily_stats table
  - Enable fast dashboard queries without expensive real-time calculations

  Requirements: 11.2
  """

  use Oban.Worker, queue: :analytics

  alias TireDispatch.Analytics
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Starting daily analytics aggregation")

    case Analytics.aggregate_daily_stats() do
      {:ok, daily_stat} ->
        Logger.info("Daily analytics aggregation complete",
          date: daily_stat.date,
          total_jobs: daily_stat.total_jobs,
          completed_jobs: daily_stat.completed_jobs,
          total_revenue_cents: daily_stat.total_revenue_cents
        )

        :ok

      {:error, changeset} ->
        Logger.error("Failed to aggregate daily analytics",
          errors: inspect(changeset.errors)
        )

        {:error, :aggregation_failed}
    end
  end
end
