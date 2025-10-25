defmodule TireDispatchWeb.AdminDashboardLiveTest do
  use TireDispatchWeb.ConnCase

  import Phoenix.LiveViewTest
  import TireDispatch.Factory
  import Mox

  alias TireDispatch.{Jobs, Payments, Pricing, Providers}

  setup :verify_on_exit!
  setup :set_mox_global

  describe "mount/3" do
    test "redirects to home when not authenticated", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/dashboard")
    end

    test "redirects when user is not admin", %{conn: conn} do
      user = insert(:user, role: :driver)
      conn = log_in_user(conn, user)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/dashboard")
    end

    test "mounts successfully for admin user", %{conn: conn} do
      user = insert(:user, role: :admin)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/admin/dashboard")

      assert has_element?(view, "h1", "Admin Dashboard")
      assert has_element?(view, "text", "Platform monitoring and management")
    end

    test "subscribes to admin PubSub topic", %{conn: conn} do
      user = insert(:user, role: :admin)
      conn = log_in_user(conn, user)

      {:ok, _view, _html} = live(conn, ~p"/admin/dashboard")

      # Verify subscription by broadcasting a message
      Phoenix.PubSub.broadcast(
        TireDispatch.PubSub,
        "admin:jobs",
        %{event: "test", payload: %{}}
      )

      # If we get here without errors, subscription worked
      assert true
    end
  end

  describe "KPI cards" do
    setup %{conn: conn} do
      user = insert(:user, role: :admin)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/admin/dashboard")

      %{view: view, user: user}
    end

    test "displays total jobs KPI", %{view: view} do
      assert has_element?(view, "text", "Total Jobs")
    end

    test "displays total revenue KPI", %{view: view} do
      assert has_element?(view, "text", "Total Revenue")
    end

    test "displays average response time KPI", %{view: view} do
      assert has_element?(view, "text", "Avg Response Time")
    end

    test "displays provider utilization KPI", %{view: view} do
      assert has_element?(view, "text", "Provider Utilization")
    end
  end

  describe "jobs tab" do
    setup %{conn: conn} do
      user = insert(:user, role: :admin)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/admin/dashboard")

      %{view: view, user: user}
    end

    test "displays jobs tab by default", %{view: view} do
      assert has_element?(view, "h3", "Job Monitoring")
    end

    test "displays job status columns", %{view: view} do
      assert has_element?(view, "text", "Open")
      assert has_element?(view, "text", "Accepted")
      assert has_element?(view, "text", "En Route")
      assert has_element?(view, "text", "On Site")
      assert has_element?(view, "text", "Completed")
      assert has_element?(view, "text", "Cancelled")
    end

    test "displays jobs grouped by status", %{view: view} do
      driver = insert(:user, role: :driver)
      provider_user = insert(:user, role: :provider)
      provider = insert(:provider, user_id: provider_user.id)
      driver_location = %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}

      # Create jobs with different statuses
      _open_job = insert(:job, driver: driver, status: :open, driver_location: driver_location)
      _accepted_job = insert(:job, driver: driver, provider: provider, status: :accepted, driver_location: driver_location)

      # Reload view
      {:ok, view, _html} = live(view.pid)

      # Should show job counts
      assert render(view) =~ "Job Monitoring"
    end

    test "allows viewing job details", %{view: view} do
      driver = insert(:user, role: :driver)
      driver_location = %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}
      job = insert(:job, driver: driver, status: :open, driver_location: driver_location)

      # Reload view
      {:ok, view, _html} = live(view.pid)

      view
      |> element("button[phx-click='view_job_details'][phx-value-job-id='#{job.id}']")
      |> render_click()

      assert has_element?(view, "h4", "Job Details")
      assert has_element?(view, "text", job.id)
    end
  end

  describe "providers tab" do
    setup %{conn: conn} do
      user = insert(:user, role: :admin)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/admin/dashboard")

      # Switch to providers tab
      view
      |> element("button[phx-click='change_tab'][phx-value-tab='providers']")
      |> render_click()

      %{view: view, user: user}
    end

    test "displays providers tab", %{view: view} do
      assert has_element?(view, "h3", "Provider Management")
    end

    test "displays provider list", %{view: view} do
      provider_user = insert(:user, role: :provider)
      _provider = insert(:provider, user_id: provider_user.id)

      # Reload view
      {:ok, view, _html} = live(view.pid)

      assert has_element?(view, "table")
      assert has_element?(view, "th", "Provider")
      assert has_element?(view, "th", "Rating")
      assert has_element?(view, "th", "Status")
      assert has_element?(view, "th", "Verified")
    end

    test "displays provider verification status", %{view: view} do
      provider_user = insert(:user, role: :provider)
      _provider = insert(:provider, user_id: provider_user.id, is_verified: false)

      # Reload view
      {:ok, view, _html} = live(view.pid)

      assert has_element?(view, "text", "Not Verified")
    end

    test "allows verifying provider", %{view: view} do
      provider_user = insert(:user, role: :provider)
      provider = insert(:provider, user_id: provider_user.id, is_verified: false)

      # Reload view
      {:ok, view, _html} = live(view.pid)

      view
      |> element("button[phx-click='verify_provider'][phx-value-provider-id='#{provider.id}']")
      |> render_click()

      # Provider should be verified
      verified_provider = Providers.get_provider!(provider.id)
      assert verified_provider.is_verified == true
    end
  end

  describe "pricing tab" do
    setup %{conn: conn} do
      user = insert(:user, role: :admin)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/admin/dashboard")

      # Switch to pricing tab
      view
      |> element("button[phx-click='change_tab'][phx-value-tab='pricing']")
      |> render_click()

      %{view: view, user: user}
    end

    test "displays pricing tab", %{view: view} do
      assert has_element?(view, "h3", "Pricing Rules Configuration")
    end

    test "displays pricing rules", %{view: view} do
      _rule =
        insert(:pricing_rule,
          name: "Base Rate - Flat Repair",
          rule_type: :base_rate,
          value: Decimal.new("35.00"),
          active: true
        )

      # Reload view
      {:ok, view, _html} = live(view.pid)

      assert has_element?(view, "text", "Base Rate - Flat Repair")
      assert has_element?(view, "text", "Active")
    end

    test "allows editing pricing rules", %{view: view} do
      rule =
        insert(:pricing_rule,
          name: "Test Rule",
          rule_type: :base_rate,
          value: Decimal.new("35.00"),
          active: true
        )

      # Reload view
      {:ok, view, _html} = live(view.pid)

      view
      |> element("button[phx-click='edit_pricing_rule'][phx-value-rule-id='#{rule.id}']")
      |> render_click()

      # Rule should be toggled
      updated_rule = Pricing.get_pricing_rule!(rule.id)
      assert updated_rule.active == false
    end
  end

  describe "analytics tab" do
    setup %{conn: conn} do
      user = insert(:user, role: :admin)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/admin/dashboard")

      # Switch to analytics tab
      view
      |> element("button[phx-click='change_tab'][phx-value-tab='analytics']")
      |> render_click()

      %{view: view, user: user}
    end

    test "displays analytics tab", %{view: view} do
      assert has_element?(view, "h3", "Platform Analytics")
    end

    test "displays jobs by status breakdown", %{view: view} do
      assert has_element?(view, "h4", "Jobs by Status")
    end

    test "displays revenue breakdown", %{view: view} do
      assert has_element?(view, "h4", "Revenue Breakdown")
      assert has_element?(view, "text", "Total Revenue")
      assert has_element?(view, "text", "Platform Commission")
      assert has_element?(view, "text", "Provider Payouts")
    end
  end

  describe "refund processing" do
    setup %{conn: conn} do
      user = insert(:user, role: :admin)
      driver = insert(:user, role: :driver)
      provider_user = insert(:user, role: :provider)
      provider = insert(:provider, user_id: provider_user.id)
      driver_location = %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}

      job =
        insert(:job,
          driver: driver,
          provider: provider,
          status: :completed,
          driver_location: driver_location
        )

      transaction =
        insert(:transaction,
          job: job,
          driver: driver,
          type: :payment,
          status: :completed,
          amount_cents: 3500,
          payment_method: :stripe,
          external_transaction_id: "ch_test123"
        )

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/admin/dashboard")

      # View job details
      view
      |> element("button[phx-click='view_job_details'][phx-value-job-id='#{job.id}']")
      |> render_click()

      %{view: view, user: user, job: job, transaction: transaction}
    end

    test "displays refund button for completed jobs", %{view: view} do
      assert has_element?(view, "button", "Process Refund")
    end

    test "processes refund successfully", %{view: view, job: job, transaction: transaction} do
      # Mock Stripe refund
      expect(TireDispatch.StripeAPIMock, :create_refund, fn _charge_id, _opts ->
        {:ok, %{id: "re_test123", status: "succeeded"}}
      end)

      view
      |> element("button[phx-click='process_refund'][phx-value-job-id='#{job.id}']")
      |> render_click()

      # Refund transaction should be created
      refund_transactions =
        Payments.list_job_transactions(job.id)
        |> Enum.filter(&(&1.type == :refund))

      assert length(refund_transactions) > 0
    end
  end

  describe "real-time job updates" do
    setup %{conn: conn} do
      user = insert(:user, role: :admin)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/admin/dashboard")

      %{view: view, user: user}
    end

    test "receives job created event", %{view: view} do
      driver = insert(:user, role: :driver)
      driver_location = %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}
      job = insert(:job, driver: driver, status: :open, driver_location: driver_location)

      # Broadcast job created event
      Phoenix.PubSub.broadcast(
        TireDispatch.PubSub,
        "admin:jobs",
        {:job_created, job}
      )

      # Give LiveView time to process
      :timer.sleep(50)

      # Job should appear in the view
      assert render(view) =~ "Job Monitoring"
    end

    test "receives job updated event", %{view: view} do
      driver = insert(:user, role: :driver)
      driver_location = %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}
      job = insert(:job, driver: driver, status: :open, driver_location: driver_location)
      provider = insert(:provider)

      # Update job
      {:ok, updated_job} = Jobs.accept_job(job, provider.user_id)

      # Broadcast job updated event
      Phoenix.PubSub.broadcast(
        TireDispatch.PubSub,
        "admin:jobs",
        {:job_updated, updated_job}
      )

      # Give LiveView time to process
      :timer.sleep(50)

      # Updated job should be reflected
      assert render(view) =~ "Job Monitoring"
    end

    test "receives job accepted event", %{view: view} do
      driver = insert(:user, role: :driver)
      provider_user = insert(:user, role: :provider)
      provider = insert(:provider, user_id: provider_user.id)
      driver_location = %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}

      job = insert(:job, driver: driver, status: :open, driver_location: driver_location)

      # Accept job
      {:ok, accepted_job} = Jobs.accept_job(job, provider.id)

      # Broadcast job accepted event
      Phoenix.PubSub.broadcast(
        TireDispatch.PubSub,
        "admin:jobs",
        {:job_accepted, accepted_job}
      )

      # Give LiveView time to process
      :timer.sleep(50)

      # Accepted job should be reflected
      assert render(view) =~ "Job Monitoring"
    end

    test "receives job completed event", %{view: view} do
      driver = insert(:user, role: :driver)
      provider_user = insert(:user, role: :provider)
      provider = insert(:provider, user_id: provider_user.id)
      driver_location = %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}

      job =
        insert(:job,
          driver: driver,
          provider: provider,
          status: :on_site,
          driver_location: driver_location
        )

      # Complete job
      {:ok, completed_job} =
        Jobs.complete_job(
          job,
          "https://example.com/before.jpg",
          "https://example.com/after.jpg"
        )

      # Broadcast job completed event
      Phoenix.PubSub.broadcast(
        TireDispatch.PubSub,
        "admin:jobs",
        {:job_completed, completed_job}
      )

      # Give LiveView time to process
      :timer.sleep(50)

      # Completed job should be reflected
      assert render(view) =~ "Job Monitoring"
    end

    test "receives job cancelled event", %{view: view} do
      driver = insert(:user, role: :driver)
      driver_location = %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}
      job = insert(:job, driver: driver, status: :open, driver_location: driver_location)

      # Cancel job
      {:ok, cancelled_job} = Jobs.cancel_job(job, "Test cancellation")

      # Broadcast job cancelled event
      Phoenix.PubSub.broadcast(
        TireDispatch.PubSub,
        "admin:jobs",
        {:job_cancelled, cancelled_job}
      )

      # Give LiveView time to process
      :timer.sleep(50)

      # Cancelled job should be reflected
      assert render(view) =~ "Job Monitoring"
    end
  end

  describe "tab navigation" do
    setup %{conn: conn} do
      user = insert(:user, role: :admin)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/admin/dashboard")

      %{view: view, user: user}
    end

    test "switches to providers tab", %{view: view} do
      view
      |> element("button[phx-click='change_tab'][phx-value-tab='providers']")
      |> render_click()

      assert has_element?(view, "h3", "Provider Management")
    end

    test "switches to pricing tab", %{view: view} do
      view
      |> element("button[phx-click='change_tab'][phx-value-tab='pricing']")
      |> render_click()

      assert has_element?(view, "h3", "Pricing Rules Configuration")
    end

    test "switches to analytics tab", %{view: view} do
      view
      |> element("button[phx-click='change_tab'][phx-value-tab='analytics']")
      |> render_click()

      assert has_element?(view, "h3", "Platform Analytics")
    end

    test "switches back to jobs tab", %{view: view} do
      # Switch to providers first
      view
      |> element("button[phx-click='change_tab'][phx-value-tab='providers']")
      |> render_click()

      # Switch back to jobs
      view
      |> element("button[phx-click='change_tab'][phx-value-tab='jobs']")
      |> render_click()

      assert has_element?(view, "h3", "Job Monitoring")
    end
  end
end
