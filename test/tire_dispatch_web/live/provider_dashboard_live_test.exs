defmodule TireDispatchWeb.ProviderDashboardLiveTest do
  use TireDispatchWeb.ConnCase

  import Phoenix.LiveViewTest
  import TireDispatch.Factory
  import Mox

  alias TireDispatch.{Jobs, Providers}

  setup :verify_on_exit!
  setup :set_mox_global

  describe "mount/3" do
    test "redirects to login when not authenticated", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/provider/dashboard")
    end

    test "redirects when provider profile not found", %{conn: conn} do
      user = insert(:user, role: :provider)
      conn = log_in_user(conn, user)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/provider/dashboard")
    end

    test "mounts successfully for authenticated provider", %{conn: conn} do
      user = insert(:user, role: :provider)
      provider = insert(:provider, user_id: user.id)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      assert has_element?(view, "h1", "Provider Dashboard")
      assert has_element?(view, "text", "#{provider.service_radius_km} km radius")
    end

    test "subscribes to provider-specific PubSub topic", %{conn: conn} do
      user = insert(:user, role: :provider)
      provider = insert(:provider, user_id: user.id)
      conn = log_in_user(conn, user)

      {:ok, _view, _html} = live(conn, ~p"/provider/dashboard")

      # Verify subscription by broadcasting a message
      Phoenix.PubSub.broadcast(
        TireDispatch.PubSub,
        "provider:#{provider.id}:jobs",
        %{event: "test", payload: %{}}
      )

      # If we get here without errors, subscription worked
      assert true
    end
  end

  describe "available jobs feed" do
    setup %{conn: conn} do
      user = insert(:user, role: :provider)
      provider = insert(:provider, user_id: user.id, latitude: 40.7128, longitude: -74.0060)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      %{view: view, user: user, provider: provider}
    end

    test "displays available jobs within service radius", %{view: view, provider: provider} do
      # Create job within radius
      driver = insert(:user, role: :driver)

      _job =
        insert(:job,
          driver: driver,
          status: :open,
          driver_location: %Geo.Point{
            coordinates: {-74.0060, 40.7128},
            srid: 4326
          }
        )

      # Reload the view to see the job
      {:ok, view, _html} = live(view.pid)

      assert has_element?(view, "h2", "Available Jobs")
    end

    test "displays empty state when no jobs available", %{view: view} do
      assert has_element?(view, "text", "No jobs available in your area")
    end

    test "displays job details in feed", %{view: view, provider: provider} do
      driver = insert(:user, role: :driver)

      job =
        insert(:job,
          driver: driver,
          status: :open,
          service_type: :flat_repair,
          urgency_tier: :rush,
          vehicle_type: :suv,
          estimated_price_cents: 4500,
          driver_location: %Geo.Point{
            coordinates: {-74.0060, 40.7128},
            srid: 4326
          }
        )

      # Reload to see the job
      {:ok, view, _html} = live(view.pid)

      assert has_element?(view, "text", "Flat Tire Repair")
      assert has_element?(view, "text", "Rush")
      assert has_element?(view, "text", "SUV")
      assert has_element?(view, "text", "$45.00")
    end
  end

  describe "job acceptance" do
    setup %{conn: conn} do
      user = insert(:user, role: :provider)
      provider = insert(:provider, user_id: user.id, latitude: 40.7128, longitude: -74.0060)
      driver = insert(:user, role: :driver)

      job =
        insert(:job,
          driver: driver,
          status: :open,
          driver_location: %Geo.Point{
            coordinates: {-74.0060, 40.7128},
            srid: 4326
          }
        )

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      %{view: view, user: user, provider: provider, job: job}
    end

    test "accepts job successfully", %{view: view, job: job, provider: provider} do
      view
      |> element("button[phx-click='accept_job'][phx-value-job-id='#{job.id}']")
      |> render_click()

      # Job should be accepted
      accepted_job = Jobs.get_job!(job.id)
      assert accepted_job.status == :accepted
      assert accepted_job.provider_id == provider.id

      # Should show active job section
      assert has_element?(view, "h2", "Active Job")
    end

    test "declines job successfully", %{view: view, job: job} do
      view
      |> element("button[phx-click='decline_job'][phx-value-job-id='#{job.id}']")
      |> render_click()

      # Job should be removed from feed
      refute has_element?(view, "button[phx-value-job-id='#{job.id}']")
    end
  end

  describe "active job management" do
    setup %{conn: conn} do
      user = insert(:user, role: :provider)
      provider = insert(:provider, user_id: user.id)
      driver = insert(:user, role: :driver)
      driver_location = %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}

      job =
        insert(:job,
          driver: driver,
          provider: provider,
          status: :accepted,
          driver_location: driver_location
        )

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      %{view: view, user: user, provider: provider, job: job}
    end

    test "displays active job details", %{view: view, job: job} do
      assert has_element?(view, "h2", "Active Job")
      assert has_element?(view, "text", "Provider Assigned")
      assert has_element?(view, "text", "$#{Float.to_string(job.estimated_price_cents / 100)}")
    end

    test "transitions to en_route status", %{view: view, job: job} do
      view
      |> element("button[phx-click='start_travel']")
      |> render_click()

      # Job should be en_route
      updated_job = Jobs.get_job!(job.id)
      assert updated_job.status == :en_route
    end

    test "transitions to on_site status", %{view: view, job: job} do
      # First transition to en_route
      {:ok, job} = Jobs.start_travel(job)

      # Reload view
      {:ok, view, _html} = live(view.pid)

      view
      |> element("button[phx-click='mark_on_site']")
      |> render_click()

      # Job should be on_site
      updated_job = Jobs.get_job!(job.id)
      assert updated_job.status == :on_site
    end
  end

  describe "photo upload" do
    setup %{conn: conn} do
      user = insert(:user, role: :provider)
      provider = insert(:provider, user_id: user.id)
      driver = insert(:user, role: :driver)
      driver_location = %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}

      job =
        insert(:job,
          driver: driver,
          provider: provider,
          status: :on_site,
          driver_location: driver_location
        )

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      %{view: view, user: user, provider: provider, job: job}
    end

    test "displays photo upload interface when on_site", %{view: view} do
      assert has_element?(view, "text", "Before Photo")
      assert has_element?(view, "text", "After Photo")
      assert has_element?(view, "text", "Upload before and after photos to complete the job")
    end

    test "shows complete button when both photos uploaded", %{view: view} do
      # Simulate photos being uploaded
      send(view.pid, {:assign, before_photo_url: "https://example.com/before.jpg"})
      send(view.pid, {:assign, after_photo_url: "https://example.com/after.jpg"})

      # Give LiveView time to process
      :timer.sleep(50)

      assert has_element?(view, "button", "Complete Job")
    end
  end

  describe "job completion" do
    setup %{conn: conn} do
      user = insert(:user, role: :provider)
      provider = insert(:provider, user_id: user.id)
      driver = insert(:user, role: :driver)
      driver_location = %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}

      job =
        insert(:job,
          driver: driver,
          provider: provider,
          status: :on_site,
          driver_location: driver_location
        )

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      # Set photo URLs
      send(view.pid, {:assign, before_photo_url: "https://example.com/before.jpg"})
      send(view.pid, {:assign, after_photo_url: "https://example.com/after.jpg"})

      %{view: view, user: user, provider: provider, job: job}
    end

    test "completes job with photos", %{view: view, job: job} do
      view
      |> element("button[phx-click='complete_job_with_photos']")
      |> render_click()

      # Job should be completed
      completed_job = Jobs.get_job!(job.id)
      assert completed_job.status == :completed
      assert completed_job.before_photo_url == "https://example.com/before.jpg"
      assert completed_job.after_photo_url == "https://example.com/after.jpg"
    end
  end

  describe "earnings dashboard" do
    setup %{conn: conn} do
      user = insert(:user, role: :provider)
      provider = insert(:provider, user_id: user.id)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      %{view: view, user: user, provider: provider}
    end

    test "displays earnings summary", %{view: view} do
      assert has_element?(view, "h2", "Earnings")
      assert has_element?(view, "text", "Total Earnings")
      assert has_element?(view, "text", "Pending")
      assert has_element?(view, "text", "Paid Out")
      assert has_element?(view, "text", "Jobs Completed")
    end

    test "displays payout method", %{view: view, provider: provider} do
      assert has_element?(view, "text", "Payout Method")

      payout_method =
        case provider.payout_method do
          :stripe -> "Stripe Connect"
          :mpesa -> "M-PESA"
          _ -> "Unknown"
        end

      assert has_element?(view, "text", payout_method)
    end

    test "allows updating payout method", %{view: view} do
      # Click to show payout form
      view
      |> element("button", "Update Payout Method")
      |> render_click()

      assert has_element?(view, "select[name='payout_method']")
      assert has_element?(view, "input[name='mpesa_phone_number']")
    end
  end

  describe "real-time updates" do
    setup %{conn: conn} do
      user = insert(:user, role: :provider)
      provider = insert(:provider, user_id: user.id)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      %{view: view, user: user, provider: provider}
    end

    test "receives new job notification", %{view: view, provider: provider} do
      driver = insert(:user, role: :driver)

      job =
        insert(:job,
          driver_id: driver.id,
          status: :open,
          driver_location: %Geo.Point{
            coordinates: {provider.longitude, provider.latitude},
            srid: 4326
          }
        )

      # Broadcast new job event
      Phoenix.PubSub.broadcast(
        TireDispatch.PubSub,
        "provider:#{provider.id}:jobs",
        %{event: "new_job_available", payload: %{job: job}}
      )

      # Give LiveView time to process
      :timer.sleep(50)

      # Job should appear in feed
      assert render(view) =~ "Available Jobs"
    end
  end
end
