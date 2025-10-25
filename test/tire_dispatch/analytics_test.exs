defmodule TireDispatch.AnalyticsTest do
  use TireDispatch.DataCase, async: true

  alias TireDispatch.Analytics

  describe "get_platform_kpis/1" do
    test "returns correct KPIs for date range with jobs" do
      # Create jobs within date range
      start_date = ~D[2024-01-01]
      end_date = ~D[2024-01-31]

      # Create jobs with specific timestamps
      job1 =
        insert(:completed_job,
          inserted_at: ~U[2024-01-15 10:00:00Z],
          final_price_cents: 5000
        )

      job2 =
        insert(:completed_job,
          inserted_at: ~U[2024-01-20 14:00:00Z],
          final_price_cents: 7000
        )

      insert(:cancelled_job, inserted_at: ~U[2024-01-25 16:00:00Z])

      # Create payment transactions
      insert(:completed_payment, job: job1, amount_cents: 5000)
      insert(:completed_payment, job: job2, amount_cents: 7000)

      kpis = Analytics.get_platform_kpis(%{start_date: start_date, end_date: end_date})

      assert kpis.total_jobs == 3
      assert kpis.completed_jobs == 2
      assert kpis.cancelled_jobs == 1
      assert kpis.total_revenue_cents == 12_000
      assert kpis.average_job_value_cents == 6000
      assert is_float(kpis.average_response_time_minutes)
      assert is_float(kpis.provider_utilization_percent)
    end

    test "returns zero values when no jobs in date range" do
      start_date = ~D[2024-01-01]
      end_date = ~D[2024-01-31]

      # Create job outside date range
      insert(:completed_job, inserted_at: ~U[2023-12-15 10:00:00Z])

      kpis = Analytics.get_platform_kpis(%{start_date: start_date, end_date: end_date})

      assert kpis.total_jobs == 0
      assert kpis.completed_jobs == 0
      assert kpis.cancelled_jobs == 0
      assert kpis.total_revenue_cents == 0
      assert kpis.average_response_time_minutes == 0.0
      assert kpis.average_job_value_cents == 0
    end

    test "calculates provider utilization correctly" do
      start_date = ~D[2024-01-01]
      end_date = ~D[2024-01-31]

      # Create 4 active verified providers
      provider1 = insert(:provider, is_active: true, is_verified: true)
      provider2 = insert(:provider, is_active: true, is_verified: true)
      insert(:provider, is_active: true, is_verified: true)
      insert(:provider, is_active: true, is_verified: true)

      # Only 2 providers have jobs
      insert(:accepted_job,
        provider: provider1.user,
        inserted_at: ~U[2024-01-15 10:00:00Z]
      )

      insert(:en_route_job,
        provider: provider2.user,
        inserted_at: ~U[2024-01-20 14:00:00Z]
      )

      kpis = Analytics.get_platform_kpis(%{start_date: start_date, end_date: end_date})

      # 2 out of 4 providers = 50%
      assert kpis.provider_utilization_percent == 50.0
    end
  end

  describe "get_regional_breakdown/1" do
    test "groups jobs by geographic region" do
      start_date = ~D[2024-01-01]
      end_date = ~D[2024-01-31]

      # Create jobs in different regions (using PostGIS coordinates)
      # Northeast quadrant (positive lat, positive long)
      northeast_location = %Geo.Point{coordinates: {10.0, 10.0}, srid: 4326}

      job1 =
        insert(:completed_job,
          driver_location: northeast_location,
          inserted_at: ~U[2024-01-15 10:00:00Z],
          final_price_cents: 5000
        )

      insert(:completed_payment, job: job1, amount_cents: 5000)

      # Northwest quadrant (positive lat, negative long)
      northwest_location = %Geo.Point{coordinates: {-10.0, 10.0}, srid: 4326}

      job2 =
        insert(:completed_job,
          driver_location: northwest_location,
          inserted_at: ~U[2024-01-20 14:00:00Z],
          final_price_cents: 7000
        )

      insert(:completed_payment, job: job2, amount_cents: 7000)

      regions = Analytics.get_regional_breakdown(%{start_date: start_date, end_date: end_date})

      assert length(regions) >= 2

      northeast_region = Enum.find(regions, fn r -> r.region == "Northeast" end)
      assert northeast_region.total_jobs >= 1
      assert northeast_region.completed_jobs >= 1

      northwest_region = Enum.find(regions, fn r -> r.region == "Northwest" end)
      assert northwest_region.total_jobs >= 1
      assert northwest_region.completed_jobs >= 1
    end

    test "returns empty list when no jobs in date range" do
      start_date = ~D[2024-01-01]
      end_date = ~D[2024-01-31]

      regions = Analytics.get_regional_breakdown(%{start_date: start_date, end_date: end_date})

      assert regions == []
    end
  end

  describe "get_provider_performance/2" do
    test "returns correct performance metrics for provider" do
      start_date = ~D[2024-01-01]
      end_date = ~D[2024-01-31]

      provider = insert(:provider, rating: Decimal.new("4.5"))

      # Create jobs for provider
      job1 =
        insert(:completed_job,
          provider: provider.user,
          inserted_at: ~U[2024-01-15 10:00:00Z],
          completed_at: ~U[2024-01-15 11:00:00Z]
        )

      job2 =
        insert(:completed_job,
          provider: provider.user,
          inserted_at: ~U[2024-01-20 14:00:00Z],
          completed_at: ~U[2024-01-20 15:30:00Z]
        )

      insert(:cancelled_job,
        provider: provider.user,
        inserted_at: ~U[2024-01-25 16:00:00Z]
      )

      # Create payout transactions
      insert(:completed_payout, provider: provider.user, job: job1, amount_cents: 4250)
      insert(:completed_payout, provider: provider.user, job: job2, amount_cents: 5950)

      performance =
        Analytics.get_provider_performance(provider.id, %{
          start_date: start_date,
          end_date: end_date
        })

      assert performance.total_jobs == 3
      assert performance.completed_jobs == 2
      assert performance.cancelled_jobs == 1
      assert performance.total_earnings_cents == 10_200
      assert performance.average_rating == 4.5
      # Completion rate: 2/3 = 66.67%
      assert_in_delta performance.completion_rate_percent, 66.67, 0.1
      assert is_float(performance.average_completion_time_minutes)
      assert performance.average_completion_time_minutes > 0
    end

    test "returns zero values when provider has no jobs" do
      start_date = ~D[2024-01-01]
      end_date = ~D[2024-01-31]

      provider = insert(:provider, rating: Decimal.new("0.0"))

      performance =
        Analytics.get_provider_performance(provider.id, %{
          start_date: start_date,
          end_date: end_date
        })

      assert performance.total_jobs == 0
      assert performance.completed_jobs == 0
      assert performance.cancelled_jobs == 0
      assert performance.total_earnings_cents == 0
      assert performance.average_rating == 0.0
      assert performance.completion_rate_percent == 0.0
      assert performance.average_completion_time_minutes == 0.0
    end

    test "calculates completion rate correctly" do
      start_date = ~D[2024-01-01]
      end_date = ~D[2024-01-31]

      provider = insert(:provider)

      # 8 completed, 2 cancelled = 80% completion rate
      for _ <- 1..8 do
        insert(:completed_job,
          provider: provider.user,
          inserted_at: ~U[2024-01-15 10:00:00Z]
        )
      end

      for _ <- 1..2 do
        insert(:cancelled_job,
          provider: provider.user,
          inserted_at: ~U[2024-01-20 14:00:00Z]
        )
      end

      performance =
        Analytics.get_provider_performance(provider.id, %{
          start_date: start_date,
          end_date: end_date
        })

      assert performance.total_jobs == 10
      assert performance.completed_jobs == 8
      assert performance.completion_rate_percent == 80.0
    end
  end

  describe "aggregate_daily_stats/0" do
    test "aggregates stats for yesterday" do
      yesterday = Date.add(Date.utc_today(), -1)
      yesterday_start = DateTime.new!(yesterday, ~T[00:00:00], "Etc/UTC")

      # Create jobs for yesterday
      job1 =
        insert(:completed_job,
          inserted_at: DateTime.add(yesterday_start, 3600, :second),
          final_price_cents: 5000
        )

      job2 =
        insert(:completed_job,
          inserted_at: DateTime.add(yesterday_start, 7200, :second),
          final_price_cents: 7000
        )

      # Create payment transactions
      insert(:completed_payment, job: job1, amount_cents: 5000)
      insert(:completed_payment, job: job2, amount_cents: 7000)

      assert {:ok, daily_stat} = Analytics.aggregate_daily_stats()

      assert daily_stat.date == yesterday
      assert daily_stat.total_jobs == 2
      assert daily_stat.completed_jobs == 2
      assert daily_stat.total_revenue_cents == 12_000
    end

    test "updates existing daily stat if already exists" do
      yesterday = Date.add(Date.utc_today(), -1)

      # Create existing daily stat
      existing_stat =
        insert(:daily_stat,
          date: yesterday,
          total_jobs: 5,
          completed_jobs: 4
        )

      yesterday_start = DateTime.new!(yesterday, ~T[00:00:00], "Etc/UTC")

      # Create new jobs
      job =
        insert(:completed_job,
          inserted_at: DateTime.add(yesterday_start, 3600, :second),
          final_price_cents: 5000
        )

      insert(:completed_payment, job: job, amount_cents: 5000)

      assert {:ok, updated_stat} = Analytics.aggregate_daily_stats()

      assert updated_stat.id == existing_stat.id
      assert updated_stat.date == yesterday
      # Should reflect actual count, not add to existing
      assert updated_stat.total_jobs == 1
      assert updated_stat.completed_jobs == 1
    end
  end

  describe "get_daily_stats/1" do
    test "returns daily stats for date range" do
      # Create daily stats for different dates
      stat1 = insert(:daily_stat, date: ~D[2024-01-15], total_jobs: 10)
      stat2 = insert(:daily_stat, date: ~D[2024-01-20], total_jobs: 15)
      insert(:daily_stat, date: ~D[2024-02-01], total_jobs: 20)

      stats =
        Analytics.get_daily_stats(%{
          start_date: ~D[2024-01-01],
          end_date: ~D[2024-01-31]
        })

      assert length(stats) == 2
      stat_dates = Enum.map(stats, & &1.date)
      assert stat1.date in stat_dates
      assert stat2.date in stat_dates
    end

    test "returns empty list when no stats in date range" do
      insert(:daily_stat, date: ~D[2024-02-01])

      stats =
        Analytics.get_daily_stats(%{
          start_date: ~D[2024-01-01],
          end_date: ~D[2024-01-31]
        })

      assert stats == []
    end

    test "orders stats by date ascending" do
      insert(:daily_stat, date: ~D[2024-01-20])
      insert(:daily_stat, date: ~D[2024-01-10])
      insert(:daily_stat, date: ~D[2024-01-15])

      stats =
        Analytics.get_daily_stats(%{
          start_date: ~D[2024-01-01],
          end_date: ~D[2024-01-31]
        })

      dates = Enum.map(stats, & &1.date)
      assert dates == Enum.sort(dates, Date)
    end
  end
end
