defmodule TireDispatch.JobsTest do
  use TireDispatch.DataCase, async: true

  alias TireDispatch.Jobs
  alias TireDispatch.Jobs.Job

  describe "create_job/2" do
    test "creates a job with valid attributes" do
      driver = insert(:driver)

      attrs = %{
        service_type: :flat_repair,
        urgency_tier: :standard,
        vehicle_type: :compact,
        driver_location: %Geo.Point{coordinates: {-87.6298, 41.8781}, srid: 4326},
        estimated_price_cents: 3500
      }

      assert {:ok, %Job{} = job} = Jobs.create_job(driver.id, attrs)
      assert job.service_type == :flat_repair
      assert job.urgency_tier == :standard
      assert job.vehicle_type == :compact
      assert job.status == :open
      assert job.driver_id == driver.id
      assert job.estimated_price_cents == 3500
    end

    test "returns error with invalid service_type" do
      driver = insert(:driver)

      attrs = %{
        service_type: :invalid_type,
        urgency_tier: :standard,
        vehicle_type: :compact,
        driver_location: %Geo.Point{coordinates: {-87.6298, 41.8781}, srid: 4326},
        estimated_price_cents: 3500
      }

      assert {:error, %Ecto.Changeset{} = changeset} = Jobs.create_job(driver.id, attrs)
      assert "is invalid" in errors_on(changeset).service_type
    end

    test "returns error when driver_location is missing" do
      driver = insert(:driver)

      attrs = %{
        service_type: :flat_repair,
        urgency_tier: :standard,
        vehicle_type: :compact,
        estimated_price_cents: 3500
      }

      assert {:error, %Ecto.Changeset{} = changeset} = Jobs.create_job(driver.id, attrs)
      assert "can't be blank" in errors_on(changeset).driver_location
    end
  end

  describe "get_job/1 and get_job!/1" do
    test "get_job/1 returns job when it exists" do
      job = insert(:job)
      assert {:ok, found_job} = Jobs.get_job(job.id)
      assert found_job.id == job.id
    end

    test "get_job!/1 returns job when it exists" do
      job = insert(:job)
      assert %Job{} = found_job = Jobs.get_job!(job.id)
      assert found_job.id == job.id
    end
  end

  describe "list_open_jobs/0" do
    test "returns only jobs with open status" do
      open_job = insert(:job, status: :open)
      insert(:accepted_job)
      insert(:completed_job)

      jobs = Jobs.list_open_jobs()

      assert length(jobs) == 1
      assert hd(jobs).id == open_job.id
    end

    test "returns empty list when no open jobs exist" do
      insert(:accepted_job)
      insert(:completed_job)

      assert Jobs.list_open_jobs() == []
    end
  end

  describe "accept_job/2" do
    test "accepts an open job and assigns provider" do
      job = insert(:job, status: :open)
      provider_user = insert(:provider_user)

      assert {:ok, %Job{} = accepted_job} = Jobs.accept_job(job, provider_user.id)
      assert accepted_job.status == :accepted
      assert accepted_job.provider_id == provider_user.id
    end

    test "returns error when job is not in open status" do
      job = insert(:accepted_job)
      provider_user = insert(:provider_user)

      assert {:error, "Job cannot be accepted from current state"} =
               Jobs.accept_job(job, provider_user.id)
    end

    test "returns error when job is already completed" do
      job = insert(:completed_job)
      provider_user = insert(:provider_user)

      assert {:error, "Job cannot be accepted from current state"} =
               Jobs.accept_job(job, provider_user.id)
    end
  end

  describe "start_travel/1" do
    test "transitions accepted job to en_route" do
      job = insert(:accepted_job)

      assert {:ok, %Job{} = updated_job} = Jobs.start_travel(job)
      assert updated_job.status == :en_route
    end

    test "returns error when job is not in accepted status" do
      job = insert(:job, status: :open)

      assert {:error, "Job cannot transition to en_route from current state"} =
               Jobs.start_travel(job)
    end
  end

  describe "mark_on_site/1" do
    test "transitions en_route job to on_site" do
      job = insert(:en_route_job)

      assert {:ok, %Job{} = updated_job} = Jobs.mark_on_site(job)
      assert updated_job.status == :on_site
    end

    test "returns error when job is not in en_route status" do
      job = insert(:accepted_job)

      assert {:error, "Job cannot transition to on_site from current state"} =
               Jobs.mark_on_site(job)
    end
  end

  describe "complete_job/3" do
    test "completes on_site job with photos" do
      job = insert(:on_site_job)
      before_url = "https://s3.amazonaws.com/test/before.jpg"
      after_url = "https://s3.amazonaws.com/test/after.jpg"

      assert {:ok, %Job{} = completed_job} = Jobs.complete_job(job, before_url, after_url)
      assert completed_job.status == :completed
      assert completed_job.before_photo_url == before_url
      assert completed_job.after_photo_url == after_url
      assert completed_job.final_price_cents == job.estimated_price_cents
      assert completed_job.completed_at != nil
    end

    test "returns error when job is not in on_site status" do
      job = insert(:en_route_job)

      assert {:error, "Job can only be completed from on_site status"} =
               Jobs.complete_job(job, "before.jpg", "after.jpg")
    end
  end

  describe "cancel_job/2" do
    test "cancels an open job" do
      job = insert(:job, status: :open)
      reason = "Driver no longer needs service"

      assert {:ok, %Job{} = cancelled_job} = Jobs.cancel_job(job, reason)
      assert cancelled_job.status == :cancelled
      assert cancelled_job.cancellation_reason == reason
    end

    test "cancels an accepted job" do
      job = insert(:accepted_job)
      reason = "Provider unavailable"

      assert {:ok, %Job{} = cancelled_job} = Jobs.cancel_job(job, reason)
      assert cancelled_job.status == :cancelled
    end

    test "returns error when trying to cancel completed job" do
      job = insert(:completed_job)

      assert {:error, "Cannot cancel a completed job"} = Jobs.cancel_job(job, "test reason")
    end
  end

  describe "update_provider_location/3" do
    test "updates provider location for a job" do
      job = insert(:accepted_job)
      lat = 41.8900
      long = -87.6400

      assert {:ok, %Job{} = updated_job} = Jobs.update_provider_location(job, lat, long)
      assert %Geo.Point{coordinates: {^long, ^lat}} = updated_job.provider_location
    end
  end

  # Note: PostGIS tests require PostGIS extension enabled in test database
  # Uncomment after enabling PostGIS in test environment
  # describe "jobs_within_radius/3" do
  #   test "returns jobs within specified radius" do
  #     # Create job at specific location
  #     driver_location = %Geo.Point{coordinates: {-87.6298, 41.8781}, srid: 4326}
  #     job = insert(:job, driver_location: driver_location)

  #     # Search near the job location (within 1km)
  #     jobs = Jobs.jobs_within_radius(41.8781, -87.6298, 1)

  #     assert length(jobs) == 1
  #     assert hd(jobs).id == job.id
  #   end

  #   test "excludes jobs outside specified radius" do
  #     # Create job at Chicago location
  #     chicago_location = %Geo.Point{coordinates: {-87.6298, 41.8781}, srid: 4326}
  #     insert(:job, driver_location: chicago_location)

  #     # Search in New York (far away)
  #     jobs = Jobs.jobs_within_radius(40.7128, -74.0060, 1)

  #     assert jobs == []
  #   end

  #   test "orders jobs by distance ascending" do
  #     # Create jobs at different distances
  #     near_location = %Geo.Point{coordinates: {-87.6298, 41.8781}, srid: 4326}
  #     far_location = %Geo.Point{coordinates: {-87.7000, 41.9000}, srid: 4326}

  #     near_job = insert(:job, driver_location: near_location)
  #     far_job = insert(:job, driver_location: far_location)

  #     # Search from near location
  #     jobs = Jobs.jobs_within_radius(41.8781, -87.6298, 50)

  #     assert length(jobs) == 2
  #     assert hd(jobs).id == near_job.id
  #     assert List.last(jobs).id == far_job.id
  #   end
  # end

  # describe "open_jobs_within_radius/3" do
  #   test "returns only open jobs within radius" do
  #     location = %Geo.Point{coordinates: {-87.6298, 41.8781}, srid: 4326}
  #     open_job = insert(:job, status: :open, driver_location: location)
  #     insert(:accepted_job, driver_location: location)

  #     jobs = Jobs.open_jobs_within_radius(41.8781, -87.6298, 1)

  #     assert length(jobs) == 1
  #     assert hd(jobs).id == open_job.id
  #   end
  # end

  # Note: PostGIS tests require PostGIS extension enabled in test database
  # Uncomment after enabling PostGIS in test environment
  # describe "calculate_distance/2" do
  #   test "calculates distance between two points" do
  #     point1 = %Geo.Point{coordinates: {-87.6298, 41.8781}, srid: 4326}
  #     point2 = %Geo.Point{coordinates: {-87.6400, 41.8900}, srid: 4326}

  #     distance = Jobs.calculate_distance(point1, point2)

  #     assert is_float(distance)
  #     assert distance > 0
  #     # Distance should be roughly 1.5km
  #     assert distance > 1000 and distance < 2000
  #   end
  # end

  describe "list_jobs_for_provider/2" do
    test "returns jobs for specific provider" do
      provider = insert(:provider_user)
      job1 = insert(:accepted_job, provider: provider)
      job2 = insert(:completed_job, provider: provider)
      insert(:accepted_job)

      jobs = Jobs.list_jobs_for_provider(provider.id)

      assert length(jobs) == 2
      job_ids = Enum.map(jobs, & &1.id)
      assert job1.id in job_ids
      assert job2.id in job_ids
    end

    test "filters jobs by status" do
      provider = insert(:provider_user)
      completed_job = insert(:completed_job, provider: provider)
      insert(:accepted_job, provider: provider)

      jobs = Jobs.list_jobs_for_provider(provider.id, status: :completed)

      assert length(jobs) == 1
      assert hd(jobs).id == completed_job.id
    end
  end
end
