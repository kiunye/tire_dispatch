defmodule TireDispatchWeb.JobChannelTest do
  use TireDispatchWeb.ChannelCase

  alias TireDispatch.Jobs
  alias TireDispatchWeb.UserSocket

  setup do
    # Create test users
    driver = insert(:driver)
    provider_user = insert(:provider_user)
    provider = insert(:provider, user: provider_user)
    unauthorized_user = insert(:driver)

    # Create a job with driver and provider
    job =
      insert(:accepted_job,
        driver: driver,
        provider: provider_user
      )

    # Generate authentication tokens
    driver_token = Phoenix.Token.sign(TireDispatchWeb.Endpoint, "user socket", driver.id)

    provider_token =
      Phoenix.Token.sign(TireDispatchWeb.Endpoint, "user socket", provider_user.id)

    unauthorized_token =
      Phoenix.Token.sign(TireDispatchWeb.Endpoint, "user socket", unauthorized_user.id)

    {:ok,
     driver: driver,
     provider_user: provider_user,
     provider: provider,
     unauthorized_user: unauthorized_user,
     job: job,
     driver_token: driver_token,
     provider_token: provider_token,
     unauthorized_token: unauthorized_token}
  end

  describe "join/3 - authorization" do
    test "driver can join their own job channel", %{
      driver_token: driver_token,
      job: job
    } do
      {:ok, socket} = connect(UserSocket, %{"token" => driver_token})

      assert {:ok, _, socket} = subscribe_and_join(socket, "jobs:#{job.id}", %{})
      assert socket.assigns.job_id == job.id
    end

    test "provider can join assigned job channel", %{
      provider_token: provider_token,
      job: job
    } do
      {:ok, socket} = connect(UserSocket, %{"token" => provider_token})

      assert {:ok, _, socket} = subscribe_and_join(socket, "jobs:#{job.id}", %{})
      assert socket.assigns.job_id == job.id
    end

    test "unauthorized user cannot join job channel", %{
      unauthorized_token: unauthorized_token,
      job: job
    } do
      {:ok, socket} = connect(UserSocket, %{"token" => unauthorized_token})

      assert {:error, %{reason: "unauthorized"}} =
               subscribe_and_join(socket, "jobs:#{job.id}", %{})
    end

    test "returns error when job does not exist", %{driver_token: driver_token} do
      {:ok, socket} = connect(UserSocket, %{"token" => driver_token})
      non_existent_job_id = 999_999

      assert {:error, %{reason: "job_not_found"}} =
               subscribe_and_join(socket, "jobs:#{non_existent_job_id}", %{})
    end
  end

  describe "handle_in/3 - update_location" do
    setup %{provider_token: provider_token, job: job} do
      {:ok, socket} = connect(UserSocket, %{"token" => provider_token})
      {:ok, _, socket} = subscribe_and_join(socket, "jobs:#{job.id}", %{})

      {:ok, socket: socket, job: job}
    end

    test "provider can update location successfully", %{socket: socket, job: job} do
      latitude = -1.2921
      longitude = 36.8219

      ref =
        push(socket, "update_location", %{
          "latitude" => latitude,
          "longitude" => longitude
        })

      assert_reply ref, :ok

      # Verify location was broadcast
      assert_broadcast "provider_location_update", %{
        job_id: job_id,
        location: %{latitude: ^latitude, longitude: ^longitude}
      }

      assert job_id == job.id

      # Verify location was saved in database
      {:ok, updated_job} = Jobs.get_job(job.id)
      assert updated_job.provider_location != nil

      %Geo.Point{coordinates: {db_long, db_lat}} = updated_job.provider_location
      assert_in_delta db_lat, latitude, 0.0001
      assert_in_delta db_long, longitude, 0.0001
    end

    test "returns error with invalid location data", %{socket: socket} do
      ref = push(socket, "update_location", %{"latitude" => "invalid", "longitude" => 36.8219})

      assert_reply ref, :error, %{reason: "Failed to update location"}
    end

    test "returns error with missing location fields", %{socket: socket} do
      ref = push(socket, "update_location", %{"latitude" => -1.2921})

      # This will cause a function clause error which gets caught
      assert_reply ref, :error, _
    end
  end

  describe "handle_in/3 - complete_job" do
    setup _context do
      # Create a job in on_site status (ready for completion)
      driver = insert(:driver)
      provider_user = insert(:provider_user)
      insert(:provider, user: provider_user)

      job =
        insert(:on_site_job,
          driver: driver,
          provider: provider_user
        )

      # Generate token for this specific provider
      provider_token =
        Phoenix.Token.sign(TireDispatchWeb.Endpoint, "user socket", provider_user.id)

      {:ok, socket} = connect(UserSocket, %{"token" => provider_token})
      {:ok, _, socket} = subscribe_and_join(socket, "jobs:#{job.id}", %{})

      {:ok, socket: socket, job: job}
    end

    test "provider can complete job with photos", %{socket: socket, job: job} do
      before_url = "https://s3.amazonaws.com/test-bucket/before-#{job.id}.jpg"
      after_url = "https://s3.amazonaws.com/test-bucket/after-#{job.id}.jpg"

      ref =
        push(socket, "complete_job", %{
          "before_photo_url" => before_url,
          "after_photo_url" => after_url
        })

      assert_reply ref, :ok

      # Verify completion was broadcast
      assert_broadcast "job_completed", %{
        job_id: broadcast_job_id,
        job: %{
          id: job_id,
          status: :completed,
          before_photo_url: ^before_url,
          after_photo_url: ^after_url
        }
      }

      assert broadcast_job_id == job.id
      assert job_id == job.id

      # Verify job was updated in database
      {:ok, completed_job} = Jobs.get_job(job.id)
      assert completed_job.status == :completed
      assert completed_job.before_photo_url == before_url
      assert completed_job.after_photo_url == after_url
      assert completed_job.completed_at != nil
    end

    test "returns error when completing job from invalid state", _context do
      # Create a job in accepted status (not ready for completion)
      driver = insert(:driver)
      provider_user = insert(:provider_user)
      insert(:provider, user: provider_user)

      job =
        insert(:accepted_job,
          driver: driver,
          provider: provider_user
        )

      # Generate token for this specific provider
      provider_token =
        Phoenix.Token.sign(TireDispatchWeb.Endpoint, "user socket", provider_user.id)

      {:ok, socket} = connect(UserSocket, %{"token" => provider_token})
      {:ok, _, socket} = subscribe_and_join(socket, "jobs:#{job.id}", %{})

      ref =
        push(socket, "complete_job", %{
          "before_photo_url" => "https://example.com/before.jpg",
          "after_photo_url" => "https://example.com/after.jpg"
        })

      assert_reply ref, :error, %{reason: reason}
      assert reason =~ "can only be completed from on_site status"
    end

    test "returns error with missing photo URLs", %{socket: socket} do
      ref = push(socket, "complete_job", %{"before_photo_url" => "https://example.com/before.jpg"})

      # This will cause a function clause error
      assert_reply ref, :error, _
    end
  end

  describe "broadcasting" do
    test "location updates are broadcast to all channel subscribers", %{
      provider_token: provider_token,
      driver_token: driver_token,
      job: job
    } do
      # Connect both provider and driver
      {:ok, provider_socket} = connect(UserSocket, %{"token" => provider_token})
      {:ok, driver_socket} = connect(UserSocket, %{"token" => driver_token})

      {:ok, _, provider_socket} = subscribe_and_join(provider_socket, "jobs:#{job.id}", %{})
      {:ok, _, _driver_socket} = subscribe_and_join(driver_socket, "jobs:#{job.id}", %{})

      latitude = -1.2921
      longitude = 36.8219

      # Provider sends location update
      ref =
        push(provider_socket, "update_location", %{
          "latitude" => latitude,
          "longitude" => longitude
        })

      assert_reply ref, :ok

      # Both provider and driver should receive the broadcast
      assert_broadcast "provider_location_update", %{
        job_id: job_id,
        location: %{latitude: ^latitude, longitude: ^longitude}
      }

      assert job_id == job.id
    end

    test "job completion is broadcast to all channel subscribers", _context do
      # Create a job in on_site status
      driver = insert(:driver)
      provider_user = insert(:provider_user)
      insert(:provider, user: provider_user)

      job =
        insert(:on_site_job,
          driver: driver,
          provider: provider_user
        )

      # Generate tokens for this specific job's users
      driver_token = Phoenix.Token.sign(TireDispatchWeb.Endpoint, "user socket", driver.id)

      provider_token =
        Phoenix.Token.sign(TireDispatchWeb.Endpoint, "user socket", provider_user.id)

      # Connect both provider and driver
      {:ok, provider_socket} = connect(UserSocket, %{"token" => provider_token})
      {:ok, driver_socket} = connect(UserSocket, %{"token" => driver_token})

      {:ok, _, provider_socket} = subscribe_and_join(provider_socket, "jobs:#{job.id}", %{})
      {:ok, _, _driver_socket} = subscribe_and_join(driver_socket, "jobs:#{job.id}", %{})

      before_url = "https://s3.amazonaws.com/test-bucket/before.jpg"
      after_url = "https://s3.amazonaws.com/test-bucket/after.jpg"

      # Provider completes job
      ref =
        push(provider_socket, "complete_job", %{
          "before_photo_url" => before_url,
          "after_photo_url" => after_url
        })

      assert_reply ref, :ok

      # Both provider and driver should receive the broadcast
      assert_broadcast "job_completed", %{
        job_id: job_id,
        job: %{status: :completed}
      }

      assert job_id == job.id
    end
  end
end
