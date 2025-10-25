defmodule TireDispatch.Analytics do
  @moduledoc """
  Analytics context for KPIs, reporting, and platform metrics.
  """

  import Ecto.Query
  alias TireDispatch.Analytics.DailyStat
  alias TireDispatch.Jobs.Job
  alias TireDispatch.Payments.Transaction
  alias TireDispatch.Providers.Provider
  alias TireDispatch.Repo

  @doc """
  Get platform-wide KPIs for a given date range.

  ## Arguments

    * `date_range` - Map with :start_date and :end_date (Date structs)

  ## Returns

    * Map with KPI metrics:
      - total_jobs: Total number of jobs
      - completed_jobs: Number of completed jobs
      - cancelled_jobs: Number of cancelled jobs
      - total_revenue_cents: Total revenue from completed jobs
      - average_response_time_minutes: Average time from job creation to acceptance
      - provider_utilization_percent: Percentage of active providers with jobs
      - average_job_value_cents: Average value of completed jobs

  ## Examples

      iex> get_platform_kpis(%{start_date: ~D[2025-01-01], end_date: ~D[2025-01-31]})
      %{
        total_jobs: 150,
        completed_jobs: 140,
        cancelled_jobs: 10,
        total_revenue_cents: 1_500_000,
        average_response_time_minutes: 12.5,
        provider_utilization_percent: 75.0,
        average_job_value_cents: 10_714
      }
  """
  def get_platform_kpis(%{start_date: start_date, end_date: end_date}) do
    {start_datetime, end_datetime} = build_datetime_range(start_date, end_date)

    job_stats = get_job_statistics(start_datetime, end_datetime)
    revenue = get_revenue_statistics(start_datetime, end_datetime)
    avg_response_time = get_average_response_time(start_datetime, end_datetime)
    provider_utilization = calculate_provider_utilization(start_datetime, end_datetime)
    average_job_value = calculate_average_job_value(revenue)

    %{
      total_jobs: job_stats.total_jobs || 0,
      completed_jobs: job_stats.completed_jobs || 0,
      cancelled_jobs: job_stats.cancelled_jobs || 0,
      total_revenue_cents: to_integer(revenue.total_revenue_cents),
      average_response_time_minutes: to_float(avg_response_time) |> Float.round(2),
      provider_utilization_percent: Float.round(provider_utilization, 2),
      average_job_value_cents: average_job_value
    }
  end

  defp build_datetime_range(start_date, end_date) do
    start_datetime = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_datetime = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")
    {start_datetime, end_datetime}
  end

  defp get_job_statistics(start_datetime, end_datetime) do
    from(j in Job,
      where: j.inserted_at >= ^start_datetime and j.inserted_at <= ^end_datetime,
      select: %{
        total_jobs: count(j.id),
        completed_jobs: fragment("COUNT(CASE WHEN ? = 'completed' THEN 1 END)", j.status),
        cancelled_jobs: fragment("COUNT(CASE WHEN ? = 'cancelled' THEN 1 END)", j.status)
      }
    )
    |> Repo.one()
  end

  defp get_revenue_statistics(start_datetime, end_datetime) do
    from(t in Transaction,
      where:
        t.type == :payment and
          t.status == :completed and
          t.inserted_at >= ^start_datetime and
          t.inserted_at <= ^end_datetime,
      select: %{
        total_revenue_cents: sum(t.amount_cents),
        count: count(t.id)
      }
    )
    |> Repo.one()
  end

  defp get_average_response_time(start_datetime, end_datetime) do
    from(j in Job,
      where:
        j.status in [:accepted, :en_route, :on_site, :completed] and
          j.inserted_at >= ^start_datetime and
          j.inserted_at <= ^end_datetime,
      select:
        fragment(
          "AVG(EXTRACT(EPOCH FROM (? - ?)) / 60)",
          j.updated_at,
          j.inserted_at
        )
    )
    |> Repo.one()
  end

  defp calculate_provider_utilization(start_datetime, end_datetime) do
    total_providers = get_total_active_providers()
    active_providers = get_active_providers_count(start_datetime, end_datetime)

    if total_providers > 0 do
      active_providers / total_providers * 100
    else
      0.0
    end
  end

  defp get_total_active_providers do
    from(p in Provider,
      where: p.is_active == true and p.is_verified == true,
      select: count(p.id)
    )
    |> Repo.one()
  end

  defp get_active_providers_count(start_datetime, end_datetime) do
    from(j in Job,
      where:
        j.status in [:accepted, :en_route, :on_site] and
          j.inserted_at >= ^start_datetime and
          j.inserted_at <= ^end_datetime,
      distinct: true,
      select: j.provider_id
    )
    |> Repo.all()
    |> Enum.reject(&is_nil/1)
    |> length()
  end

  defp calculate_average_job_value(revenue) do
    if revenue.count > 0 do
      div(revenue.total_revenue_cents || 0, revenue.count)
    else
      0
    end
  end

  @doc """
  Get regional breakdown of jobs and revenue.

  ## Arguments

    * `date_range` - Map with :start_date and :end_date (Date structs)

  ## Returns

    * List of maps with regional statistics grouped by approximate location

  ## Examples

      iex> get_regional_breakdown(%{start_date: ~D[2025-01-01], end_date: ~D[2025-01-31]})
      [
        %{
          region: "North",
          total_jobs: 50,
          completed_jobs: 45,
          total_revenue_cents: 500_000
        },
        ...
      ]
  """
  def get_regional_breakdown(%{start_date: start_date, end_date: end_date}) do
    start_datetime = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_datetime = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")

    # Group jobs by approximate geographic regions using PostGIS
    # This is a simplified version - in production, you'd use proper region boundaries
    from(j in Job,
      where: j.inserted_at >= ^start_datetime and j.inserted_at <= ^end_datetime,
      left_join: t in Transaction,
      on: t.job_id == j.id and t.type == :payment and t.status == :completed,
      group_by:
        fragment(
          "CASE
            WHEN ST_Y(?) >= 0 AND ST_X(?) >= 0 THEN 'Northeast'
            WHEN ST_Y(?) >= 0 AND ST_X(?) < 0 THEN 'Northwest'
            WHEN ST_Y(?) < 0 AND ST_X(?) >= 0 THEN 'Southeast'
            ELSE 'Southwest'
          END",
          j.driver_location,
          j.driver_location,
          j.driver_location,
          j.driver_location,
          j.driver_location,
          j.driver_location
        ),
      select: %{
        region:
          fragment(
            "CASE
              WHEN ST_Y(?) >= 0 AND ST_X(?) >= 0 THEN 'Northeast'
              WHEN ST_Y(?) >= 0 AND ST_X(?) < 0 THEN 'Northwest'
              WHEN ST_Y(?) < 0 AND ST_X(?) >= 0 THEN 'Southeast'
              ELSE 'Southwest'
            END",
            j.driver_location,
            j.driver_location,
            j.driver_location,
            j.driver_location,
            j.driver_location,
            j.driver_location
          ),
        total_jobs: count(j.id),
        completed_jobs: fragment("COUNT(CASE WHEN ? = 'completed' THEN 1 END)", j.status),
        total_revenue_cents: sum(t.amount_cents)
      }
    )
    |> Repo.all()
    |> Enum.map(fn region ->
      %{
        region: region.region,
        total_jobs: region.total_jobs || 0,
        completed_jobs: region.completed_jobs || 0,
        total_revenue_cents: region.total_revenue_cents || 0
      }
    end)
  end

  @doc """
  Get performance metrics for a specific provider.

  ## Arguments

    * `provider_id` - Provider ID
    * `date_range` - Map with :start_date and :end_date (Date structs)

  ## Returns

    * Map with provider performance metrics:
      - total_jobs: Total jobs accepted
      - completed_jobs: Jobs completed
      - cancelled_jobs: Jobs cancelled
      - total_earnings_cents: Total earnings from completed jobs
      - average_rating: Average rating (if ratings exist)
      - completion_rate_percent: Percentage of accepted jobs completed
      - average_completion_time_minutes: Average time from acceptance to completion

  ## Examples

      iex> get_provider_performance(provider_id, %{start_date: ~D[2025-01-01], end_date: ~D[2025-01-31]})
      %{
        total_jobs: 25,
        completed_jobs: 23,
        cancelled_jobs: 2,
        total_earnings_cents: 250_000,
        average_rating: 4.8,
        completion_rate_percent: 92.0,
        average_completion_time_minutes: 45.5
      }
  """
  def get_provider_performance(provider_id, %{start_date: start_date, end_date: end_date}) do
    {start_datetime, end_datetime} = build_datetime_range(start_date, end_date)

    job_stats = get_provider_job_statistics(provider_id, start_datetime, end_datetime)
    earnings = get_provider_earnings(provider_id, start_datetime, end_datetime)
    average_rating = get_provider_rating(provider_id)
    completion_rate = calculate_completion_rate(job_stats)
    avg_completion_time = get_provider_completion_time(provider_id, start_datetime, end_datetime)

    %{
      total_jobs: job_stats.total_jobs || 0,
      completed_jobs: job_stats.completed_jobs || 0,
      cancelled_jobs: job_stats.cancelled_jobs || 0,
      total_earnings_cents: earnings || 0,
      average_rating: Float.round(average_rating, 2),
      completion_rate_percent: Float.round(completion_rate, 2),
      average_completion_time_minutes: Float.round(avg_completion_time || 0.0, 2)
    }
  end

  defp get_provider_job_statistics(provider_id, start_datetime, end_datetime) do
    from(j in Job,
      where:
        j.provider_id == ^provider_id and
          j.inserted_at >= ^start_datetime and
          j.inserted_at <= ^end_datetime,
      select: %{
        total_jobs: count(j.id),
        completed_jobs: fragment("COUNT(CASE WHEN ? = 'completed' THEN 1 END)", j.status),
        cancelled_jobs: fragment("COUNT(CASE WHEN ? = 'cancelled' THEN 1 END)", j.status)
      }
    )
    |> Repo.one()
  end

  defp get_provider_earnings(provider_id, start_datetime, end_datetime) do
    from(t in Transaction,
      where:
        t.provider_id == ^provider_id and
          t.type == :payout and
          t.status == :completed and
          t.inserted_at >= ^start_datetime and
          t.inserted_at <= ^end_datetime,
      select: sum(t.amount_cents)
    )
    |> Repo.one()
  end

  defp get_provider_rating(provider_id) do
    case Repo.get(Provider, provider_id) do
      nil -> 0.0
      provider -> Decimal.to_float(provider.rating || Decimal.new(0))
    end
  end

  defp calculate_completion_rate(job_stats) do
    if job_stats.total_jobs > 0 do
      job_stats.completed_jobs / job_stats.total_jobs * 100
    else
      0.0
    end
  end

  defp get_provider_completion_time(provider_id, start_datetime, end_datetime) do
    from(j in Job,
      where:
        j.provider_id == ^provider_id and
          j.status == :completed and
          j.completed_at >= ^start_datetime and
          j.completed_at <= ^end_datetime and
          not is_nil(j.completed_at),
      select:
        fragment(
          "AVG(EXTRACT(EPOCH FROM (? - ?)) / 60)",
          j.completed_at,
          j.inserted_at
        )
    )
    |> Repo.one()
  end

  @doc """
  Aggregate daily statistics for the platform.

  This function calculates and stores aggregated statistics for fast dashboard queries.
  Should be run daily via Oban worker.

  ## Returns

    * `{:ok, daily_stat}` on success
    * `{:error, reason}` on failure
  """
  def aggregate_daily_stats do
    yesterday = Date.add(Date.utc_today(), -1)
    date_range = %{start_date: yesterday, end_date: yesterday}

    # Get platform KPIs for yesterday
    kpis = get_platform_kpis(date_range)

    # Store aggregated data in daily_stats table
    attrs = Map.put(kpis, :date, yesterday)

    case Repo.get_by(DailyStat, date: yesterday) do
      nil ->
        %DailyStat{}
        |> DailyStat.changeset(attrs)
        |> Repo.insert()

      existing_stat ->
        existing_stat
        |> DailyStat.changeset(attrs)
        |> Repo.update()
    end
    |> tap(&log_aggregation_result(yesterday, &1))
  end

  defp log_aggregation_result(date, {:ok, _stat}) do
    require Logger
    Logger.info("Daily stats aggregated successfully", %{date: date})
  end

  defp log_aggregation_result(date, {:error, changeset}) do
    require Logger

    Logger.error("Failed to aggregate daily stats", %{
      date: date,
      errors: inspect(changeset.errors)
    })
  end

  @doc """
  Get aggregated daily stats for a date range.

  This function retrieves pre-aggregated statistics from the daily_stats table
  for fast dashboard queries.

  ## Arguments

    * `date_range` - Map with :start_date and :end_date (Date structs)

  ## Returns

    * List of DailyStat structs

  ## Examples

      iex> get_daily_stats(%{start_date: ~D[2025-01-01], end_date: ~D[2025-01-31]})
      [%DailyStat{date: ~D[2025-01-01], total_jobs: 10, ...}, ...]
  """
  def get_daily_stats(%{start_date: start_date, end_date: end_date}) do
    from(ds in DailyStat,
      where: ds.date >= ^start_date and ds.date <= ^end_date,
      order_by: [asc: ds.date]
    )
    |> Repo.all()
  end

  # Helper functions for type conversion

  defp to_float(nil), do: 0.0
  defp to_float(value) when is_float(value), do: value
  defp to_float(%Decimal{} = value), do: Decimal.to_float(value)
  defp to_float(value) when is_integer(value), do: value * 1.0

  defp to_integer(nil), do: 0
  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(%Decimal{} = value), do: Decimal.to_integer(value)
  defp to_integer(value) when is_float(value), do: round(value)
end
