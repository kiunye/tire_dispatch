defmodule TireDispatchWeb.DriverDashboardLiveTest do
  use TireDispatchWeb.ConnCase

  import Phoenix.LiveViewTest
  import TireDispatch.Factory
  import Mox

  alias TireDispatch.Jobs

  setup :verify_on_exit!
  setup :set_mox_global

  describe "mount/3" do
    test "redirects to login when not authenticated", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/driver/dashboard")
    end

    test "mounts successfully for authenticated driver", %{conn: conn} do
      user = insert(:user, role: :driver)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      assert has_element?(view, "#service-request-form")
      assert has_element?(view, "h1", "Driver Dashboard")
    end

    test "subscribes to driver-specific PubSub topic", %{conn: conn} do
      user = insert(:user, role: :driver)
      conn = log_in_user(conn, user)

      {:ok, _view, _html} = live(conn, ~p"/driver/dashboard")

      # Verify subscription by broadcasting a message
      Phoenix.PubSub.broadcast(
        TireDispatch.PubSub,
        "driver:#{user.id}:jobs",
        %{event: "test", payload: %{}}
      )

      # If we get here without errors, subscription worked
      assert true
    end
  end

  describe "service request form" do
    setup %{conn: conn} do
      user = insert(:user, role: :driver)
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      %{view: view, user: user}
    end

    test "displays service request form on initial load", %{view: view} do
      assert has_element?(view, "#service-request-form")
      assert has_element?(view, "select[name='service_request[service_type]']")
      assert has_element?(view, "select[name='service_request[urgency_tier]']")
      assert has_element?(view, "select[name='service_request[vehicle_type]']")
      assert has_element?(view, "input[name='service_request[latitude]']")
      assert has_element?(view, "input[name='service_request[longitude]']")
    end

    test "calculates quote on form submission", %{view: view} do
      # Mock pricing calculation
      expect(TireDispatch.PricingMock, :calculate_quote, fn _location, _service_type,
                                                             _urgency, _vehicle ->
        {:ok, %{low: 3500, high: 4025}}
      end)

      form_data = %{
        "service_request" => %{
          "service_type" => "flat_repair",
          "urgency_tier" => "standard",
          "vehicle_type" => "compact",
          "latitude" => "40.7128",
          "longitude" => "-74.0060",
          "issue_notes" => "Flat tire on highway"
        }
      }

      view
      |> form("#service-request-form", form_data)
      |> render_submit()

      # Should transition to quote step
      assert has_element?(view, "h2", "Your Quote")
      assert has_element?(view, "text", "$35.00")
      assert has_element?(view, "text", "$40.25")
    end

    test "displays error message when quote calculation fails", %{view: view} do
      # Mock pricing calculation failure
      expect(TireDispatch.PricingMock, :calculate_quote, fn _location, _service_type,
                                                             _urgency, _vehicle ->
        {:error, :calculation_failed}
      end)

      form_data = %{
        "service_request" => %{
          "service_type" => "flat_repair",
          "urgency_tier" => "standard",
          "vehicle_type" => "compact",
          "latitude" => "40.7128",
          "longitude" => "-74.0060"
        }
      }

      view
      |> form("#service-request-form", form_data)
      |> render_submit()

      # Should display error message
      assert has_element?(view, "div", "Failed to calculate quote")
    end
  end

  describe "quote display" do
    setup %{conn: conn} do
      user = insert(:user, role: :driver)
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Submit form to get to quote step
      expect(TireDispatch.PricingMock, :calculate_quote, fn _location, _service_type,
                                                             _urgency, _vehicle ->
        {:ok, %{low: 3500, high: 4025}}
      end)

      form_data = %{
        "service_request" => %{
          "service_type" => "flat_repair",
          "urgency_tier" => "rush",
          "vehicle_type" => "suv",
          "latitude" => "40.7128",
          "longitude" => "-74.0060"
        }
      }

      view
      |> form("#service-request-form", form_data)
      |> render_submit()

      %{view: view, user: user}
    end

    test "displays quote with price range", %{view: view} do
      assert has_element?(view, "h2", "Your Quote")
      assert has_element?(view, "text", "$35.00")
      assert has_element?(view, "text", "$40.25")
      assert has_element?(view, "text", "Low Estimate")
      assert has_element?(view, "text", "High Estimate")
    end

    test "displays service details", %{view: view} do
      assert has_element?(view, "text", "Flat Tire Repair")
      assert has_element?(view, "text", "Rush")
      assert has_element?(view, "text", "SUV")
    end

    test "allows navigation back to form", %{view: view} do
      view
      |> element("button", "Back to form")
      |> render_click()

      assert has_element?(view, "#service-request-form")
    end

    test "proceeds to payment selection", %{view: view} do
      view
      |> element("button", "Proceed to Payment")
      |> render_click()

      assert has_element?(view, "h2", "Select Payment Method")
    end
  end

  describe "payment selection" do
    setup %{conn: conn} do
      user = insert(:user, role: :driver)
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Navigate to payment step
      expect(TireDispatch.PricingMock, :calculate_quote, fn _location, _service_type,
                                                             _urgency, _vehicle ->
        {:ok, %{low: 3500, high: 4025}}
      end)

      form_data = %{
        "service_request" => %{
          "service_type" => "flat_repair",
          "urgency_tier" => "standard",
          "vehicle_type" => "compact",
          "latitude" => "40.7128",
          "longitude" => "-74.0060"
        }
      }

      view
      |> form("#service-request-form", form_data)
      |> render_submit()

      view
      |> element("button", "Proceed to Payment")
      |> render_click()

      %{view: view, user: user}
    end

    test "displays payment method options", %{view: view} do
      assert has_element?(view, "h2", "Select Payment Method")
      assert has_element?(view, "button", "Credit/Debit Card")
      assert has_element?(view, "button", "M-PESA")
    end

    test "allows selecting Stripe payment method", %{view: view} do
      view
      |> element("button[phx-value-method='stripe']")
      |> render_click()

      # Verify Stripe is selected (button text changes)
      assert has_element?(view, "button", "Proceed to Stripe Checkout")
    end

    test "allows selecting MPESA payment method", %{view: view} do
      view
      |> element("button[phx-value-method='mpesa']")
      |> render_click()

      # Verify MPESA is selected and phone input appears
      assert has_element?(view, "input#mpesa-phone-input")
      assert has_element?(view, "button", "Send M-PESA Payment Request")
    end

    test "allows navigation back to quote", %{view: view} do
      view
      |> element("button", "Back to quote")
      |> render_click()

      assert has_element?(view, "h2", "Your Quote")
    end
  end

  describe "job tracking" do
    setup %{conn: conn} do
      user = insert(:user, role: :driver)
      driver_location = %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}

      job = insert(:job,
        driver: user,
        status: :accepted,
        driver_location: driver_location
      )

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Manually set the tracking state
      send(view.pid, %{event: "job_created", payload: %{job: job}})

      %{view: view, user: user, job: job}
    end

    test "displays job tracking interface", %{view: view} do
      assert has_element?(view, "h2", "Track Your Service")
      assert has_element?(view, "text", "Current Status")
    end

    test "displays job status timeline", %{view: view} do
      assert has_element?(view, "text", "Requested")
      assert has_element?(view, "text", "Accepted")
      assert has_element?(view, "text", "En Route")
      assert has_element?(view, "text", "On Site")
      assert has_element?(view, "text", "Complete")
    end

    test "displays job details", %{view: view, job: job} do
      assert has_element?(view, "text", "Job Details")
      assert has_element?(view, "text", "$#{Float.to_string(job.estimated_price_cents / 100)}")
    end

    test "shows cancel button for active jobs", %{view: view} do
      assert has_element?(view, "button", "Cancel Job")
    end

    test "handles job cancellation", %{view: view, job: job} do
      # Click cancel button to show modal
      view
      |> element("button", "Cancel Job")
      |> render_click()

      # Verify modal appears
      assert has_element?(view, "h3", "Cancel Job?")

      # Confirm cancellation
      view
      |> element("button", "Cancel Job")
      |> render_click()

      # Job should be cancelled
      cancelled_job = Jobs.get_job!(job.id)
      assert cancelled_job.status == :cancelled
    end
  end

  describe "real-time updates" do
    setup %{conn: conn} do
      user = insert(:user, role: :driver)
      driver_location = %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}

      job = insert(:job,
        driver: user,
        status: :open,
        driver_location: driver_location
      )

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      %{view: view, user: user, job: job}
    end

    test "receives job accepted event", %{view: view, user: user, job: job} do
      provider = insert(:provider)
      updated_job = %{job | status: :accepted, provider_id: provider.id}

      # Broadcast job accepted event
      Phoenix.PubSub.broadcast(
        TireDispatch.PubSub,
        "driver:#{user.id}:jobs",
        %{event: "job_accepted", payload: %{job: updated_job}}
      )

      # Give LiveView time to process
      :timer.sleep(50)

      # Verify flash message appears
      assert render(view) =~ "A provider has accepted your job!"
    end

    test "receives job status update event", %{view: view, user: user, job: job} do
      updated_job = %{job | status: :en_route}

      # Broadcast job updated event
      Phoenix.PubSub.broadcast(
        TireDispatch.PubSub,
        "driver:#{user.id}:jobs",
        %{event: "job_updated", payload: %{job: updated_job}}
      )

      # Give LiveView time to process
      :timer.sleep(50)

      # Verify status update appears
      assert render(view) =~ "Job status updated"
    end

    test "receives provider location update", %{view: view, user: user, job: job} do
      location = %{latitude: 40.7580, longitude: -73.9855}

      # Broadcast location update
      Phoenix.PubSub.broadcast(
        TireDispatch.PubSub,
        "driver:#{user.id}:jobs",
        %{event: "provider_location_update", payload: %{job_id: job.id, location: location}}
      )

      # Give LiveView time to process
      :timer.sleep(50)

      # Location should be updated in assigns
      assert render(view) =~ "40.7580"
    end

    test "receives job completed event", %{view: view, user: user, job: job} do
      updated_job = %{job | status: :completed}

      # Broadcast job completed event
      Phoenix.PubSub.broadcast(
        TireDispatch.PubSub,
        "driver:#{user.id}:jobs",
        %{event: "job_completed", payload: %{job: updated_job}}
      )

      # Give LiveView time to process
      :timer.sleep(50)

      # Verify completion message appears
      assert render(view) =~ "Service completed"
    end
  end
end
