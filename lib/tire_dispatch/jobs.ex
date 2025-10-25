defmodule TireDispatch.Jobs do
  @moduledoc """
  The Jobs context handles tire repair and replacement job lifecycle management.

  This context manages job creation, state transitions, geographic queries,
  and real-time broadcasting of job events via Phoenix.PubSub.
  """

  import Ecto.Query, warn: false

  alias TireDispatch.Jobs.Job
  alias TireDispatch.Repo

  require Logger

  @doc """
  Creates a new tire repair job for a driver.

  ## Arguments

    * `driver_id` - UUID of the driver requesting service
    * `attrs` - Map with service_type, urgency_tier, vehicle_type, driver_location, estimated_price_cents

  ## Returns

    * `{:ok, job}` on success
    * `{:error, changeset}` if validation fails

  ## Examples

      iex> create_job(driver_id, %{
        service_type: :flat_repair,
        urgency_tier: :standard,
        vehicle_type: :compact,
        driver_location: %Geo.Point{coordinates: {-87.6298, 41.8781}, srid: 4326},
        estimated_price_cents: 3500
      })
      {:ok, %Job{}}

  """
  def create_job(driver_id, attrs) do
    attrs = Map.put(attrs, :driver_id, driver_id)

    result =
      %Job{}
      |> Job.changeset(attrs)
      |> Repo.insert()
      |> tap(&broadcast_job_created/1)

    case result do
      {:ok, job} ->
        Logger.info("Job created successfully",
          job_id: job.id,
          driver_id: driver_id,
          service_type: job.service_type,
          urgency_tier: job.urgency_tier,
          status: job.status
        )

        # Emit telemetry event
        :telemetry.execute(
          [:tire_dispatch, :jobs, :created],
          %{count: 1},
          %{
            job_id: job.id,
            driver_id: driver_id,
            service_type: job.service_type,
            urgency_tier: job.urgency_tier
          }
        )

        {:ok, job}

      {:error, changeset} ->
        Logger.error("Failed to create job",
          driver_id: driver_id,
          errors: inspect(changeset.errors)
        )

        {:error, changeset}
    end
  end

  @doc """
  Gets a single job by ID.

  ## Arguments

    * `id` - UUID of the job

  ## Returns

    * `{:ok, job}` if found
    * `{:error, :not_found}` if not found
  """
  def get_job(id) do
    case Repo.get(Job, id) do
      nil -> {:error, :not_found}
      job -> {:ok, job}
    end
  end

  @doc """
  Gets a single job by ID.

  Raises `Ecto.NoResultsError` if the Job does not exist.

  ## Examples

      iex> get_job!(123)
      %Job{}

      iex> get_job!(456)
      ** (Ecto.NoResultsError)

  """
  def get_job!(id) do
    Repo.get!(Job, id)
  end

  @doc """
  Gets a single job by ID with preloaded associations.

  ## Examples

      iex> get_job_with_assocs!(123)
      %Job{driver: %User{}, provider: %User{}}

  """
  def get_job_with_assocs!(id) do
    Job
    |> Repo.get!(id)
    |> Repo.preload([:driver, :provider])
  end

  @doc """
  Lists all jobs regardless of status.

  ## Examples

      iex> list_all_jobs()
      [%Job{}, ...]

  """
  def list_all_jobs do
    from(j in Job,
      order_by: [desc: j.inserted_at],
      preload: [:driver, :provider]
    )
    |> Repo.all()
  end

  @doc """
  Lists all open jobs (status: :open).

  ## Examples

      iex> list_open_jobs()
      [%Job{status: :open}, ...]

  """
  def list_open_jobs do
    from(j in Job,
      where: j.status == :open,
      order_by: [desc: j.inserted_at],
      preload: [:driver]
    )
    |> Repo.all()
  end

  @doc """
  Lists jobs for a specific provider with optional filters.

  ## Arguments

    * `provider_id` - UUID of the provider
    * `filters` - Keyword list of filters (status, date_range, etc.)

  ## Examples

      iex> list_jobs_for_provider(provider_id, status: :completed)
      [%Job{provider_id: ^provider_id, status: :completed}, ...]

  """
  def list_jobs_for_provider(provider_id, filters \\ []) do
    Job
    |> where([j], j.provider_id == ^provider_id)
    |> apply_filters(filters)
    |> order_by([j], desc: j.inserted_at)
    |> preload([:driver])
    |> Repo.all()
  end

  # Private helper to apply filters to queries
  defp apply_filters(query, []), do: query

  defp apply_filters(query, [{:status, status} | rest]) do
    query
    |> where([j], j.status == ^status)
    |> apply_filters(rest)
  end

  defp apply_filters(query, [{:date_range, {start_date, end_date}} | rest]) do
    query
    |> where([j], j.inserted_at >= ^start_date and j.inserted_at <= ^end_date)
    |> apply_filters(rest)
  end

  defp apply_filters(query, [_ | rest]), do: apply_filters(query, rest)

  @doc """
  Accepts a job and assigns it to a provider.

  Only jobs with status :open can be accepted.

  ## Arguments

    * `job` - The job struct to accept
    * `provider_id` - UUID of the provider accepting the job

  ## Returns

    * `{:ok, job}` on success
    * `{:error, reason}` if state transition is invalid

  ## Examples

      iex> accept_job(%Job{status: :open}, provider_id)
      {:ok, %Job{status: :accepted, provider_id: provider_id}}

      iex> accept_job(%Job{status: :accepted}, provider_id)
      {:error, "Job cannot be accepted from current state"}

  """
  def accept_job(%Job{status: :open} = job, provider_id) do
    result =
      job
      |> Job.status_changeset(%{status: :accepted, provider_id: provider_id})
      |> Repo.update()
      |> tap(&broadcast_job_accepted/1)

    case result do
      {:ok, updated_job} ->
        # Calculate response time (time from creation to acceptance)
        response_time =
          DateTime.diff(updated_job.updated_at, updated_job.inserted_at, :millisecond)

        Logger.info("Job accepted by provider",
          job_id: job.id,
          provider_id: provider_id,
          driver_id: job.driver_id,
          previous_status: :open,
          new_status: :accepted,
          response_time_ms: response_time
        )

        # Emit telemetry event
        :telemetry.execute(
          [:tire_dispatch, :jobs, :accepted],
          %{count: 1, response_time: response_time},
          %{
            job_id: job.id,
            provider_id: provider_id,
            driver_id: job.driver_id,
            service_type: job.service_type
          }
        )

        {:ok, updated_job}

      {:error, changeset} ->
        Logger.error("Failed to accept job",
          job_id: job.id,
          provider_id: provider_id,
          errors: inspect(changeset.errors)
        )

        {:error, changeset}
    end
  end

  def accept_job(%Job{} = job, provider_id) do
    Logger.warning("Invalid job state transition attempted",
      job_id: job.id,
      provider_id: provider_id,
      current_status: job.status,
      attempted_action: :accept
    )

    {:error, "Job cannot be accepted from current state"}
  end

  @doc """
  Transitions job to :en_route status when provider starts traveling.

  Only jobs with status :accepted can transition to :en_route.

  ## Examples

      iex> start_travel(%Job{status: :accepted})
      {:ok, %Job{status: :en_route}}

  """
  def start_travel(%Job{status: :accepted} = job) do
    result =
      job
      |> Job.status_changeset(%{status: :en_route})
      |> Repo.update()
      |> tap(&broadcast_job_updated/1)

    case result do
      {:ok, updated_job} ->
        Logger.info("Provider started traveling to job",
          job_id: job.id,
          provider_id: job.provider_id,
          driver_id: job.driver_id,
          previous_status: :accepted,
          new_status: :en_route
        )

        {:ok, updated_job}

      {:error, changeset} ->
        Logger.error("Failed to start travel",
          job_id: job.id,
          errors: inspect(changeset.errors)
        )

        {:error, changeset}
    end
  end

  def start_travel(%Job{} = job) do
    Logger.warning("Invalid job state transition attempted",
      job_id: job.id,
      current_status: job.status,
      attempted_action: :start_travel
    )

    {:error, "Job cannot transition to en_route from current state"}
  end

  @doc """
  Marks job as :on_site when provider arrives at location.

  Only jobs with status :en_route can transition to :on_site.

  ## Examples

      iex> mark_on_site(%Job{status: :en_route})
      {:ok, %Job{status: :on_site}}

  """
  def mark_on_site(%Job{status: :en_route} = job) do
    result =
      job
      |> Job.status_changeset(%{status: :on_site})
      |> Repo.update()
      |> tap(&broadcast_job_updated/1)

    case result do
      {:ok, updated_job} ->
        Logger.info("Provider arrived on site",
          job_id: job.id,
          provider_id: job.provider_id,
          driver_id: job.driver_id,
          previous_status: :en_route,
          new_status: :on_site
        )

        {:ok, updated_job}

      {:error, changeset} ->
        Logger.error("Failed to mark on site",
          job_id: job.id,
          errors: inspect(changeset.errors)
        )

        {:error, changeset}
    end
  end

  def mark_on_site(%Job{} = _job) do
    {:error, "Job cannot transition to on_site from current state"}
  end

  @doc """
  Completes a job with before and after photos.

  Only jobs with status :on_site can be completed.

  ## Arguments

    * `job` - The job struct to complete
    * `before_photo_url` - S3 URL of before photo
    * `after_photo_url` - S3 URL of after photo

  ## Returns

    * `{:ok, job}` on success
    * `{:error, changeset}` if validation fails

  ## Examples

      iex> complete_job(%Job{status: :on_site}, "https://...", "https://...")
      {:ok, %Job{status: :completed, completed_at: ~U[...]}}

  """
  def complete_job(%Job{status: :on_site} = job, before_photo_url, after_photo_url) do
    result =
      job
      |> Job.completion_changeset(%{
        status: :completed,
        before_photo_url: before_photo_url,
        after_photo_url: after_photo_url,
        final_price_cents: job.estimated_price_cents,
        completed_at: DateTime.utc_now(:microsecond)
      })
      |> Repo.update()
      |> tap(&broadcast_job_completed/1)

    case result do
      {:ok, completed_job} ->
        # Calculate completion time (time from creation to completion)
        completion_time =
          DateTime.diff(completed_job.completed_at, completed_job.inserted_at, :millisecond)

        Logger.info("Job completed successfully",
          job_id: job.id,
          provider_id: job.provider_id,
          driver_id: job.driver_id,
          final_price_cents: completed_job.final_price_cents,
          service_type: job.service_type,
          completed_at: completed_job.completed_at,
          completion_time_ms: completion_time
        )

        # Emit telemetry event
        :telemetry.execute(
          [:tire_dispatch, :jobs, :completed],
          %{count: 1, completion_time: completion_time},
          %{
            job_id: job.id,
            provider_id: job.provider_id,
            driver_id: job.driver_id,
            service_type: job.service_type,
            final_price_cents: completed_job.final_price_cents
          }
        )

        {:ok, completed_job}

      {:error, changeset} ->
        Logger.error("Failed to complete job",
          job_id: job.id,
          provider_id: job.provider_id,
          errors: inspect(changeset.errors)
        )

        {:error, changeset}
    end
  end

  def complete_job(%Job{} = job, _before_photo_url, _after_photo_url) do
    Logger.warning("Invalid job state transition attempted",
      job_id: job.id,
      current_status: job.status,
      attempted_action: :complete
    )

    {:error, "Job can only be completed from on_site status"}
  end

  @doc """
  Confirms payment for a job after successful payment processing.

  This transitions the job from :open to :payment_confirmed status,
  indicating that payment has been received and the job is ready for
  provider acceptance.

  ## Arguments

    * `job` - The job struct to confirm payment for

  ## Returns

    * `{:ok, job}` on success
    * `{:error, changeset}` if validation fails

  ## Examples

      iex> confirm_payment(%Job{status: :open})
      {:ok, %Job{status: :payment_confirmed}}

  """
  def confirm_payment(%Job{} = job) do
    job
    |> Job.status_changeset(%{status: :payment_confirmed})
    |> Repo.update()
    |> tap(&broadcast_job_updated/1)
    |> tap(&send_payment_confirmation_notification/1)
  end

  @doc """
  Cancels a job with a reason.

  Jobs can be cancelled from any status except :completed.

  ## Arguments

    * `job` - The job struct to cancel
    * `reason` - String describing cancellation reason

  ## Returns

    * `{:ok, job}` on success
    * `{:error, reason}` if job is already completed

  ## Examples

      iex> cancel_job(%Job{status: :open}, "Driver no longer needs service")
      {:ok, %Job{status: :cancelled, cancellation_reason: "..."}}

  """
  def cancel_job(%Job{status: :completed} = job, _reason) do
    Logger.warning("Attempted to cancel completed job",
      job_id: job.id,
      current_status: :completed
    )

    {:error, "Cannot cancel a completed job"}
  end

  def cancel_job(%Job{} = job, reason) do
    result =
      job
      |> Job.status_changeset(%{status: :cancelled})
      |> Ecto.Changeset.put_change(:cancellation_reason, reason)
      |> Repo.update()
      |> tap(&broadcast_job_cancelled/1)

    case result do
      {:ok, cancelled_job} ->
        Logger.info("Job cancelled",
          job_id: job.id,
          driver_id: job.driver_id,
          provider_id: job.provider_id,
          previous_status: job.status,
          cancellation_reason: reason
        )

        # Emit telemetry event
        :telemetry.execute(
          [:tire_dispatch, :jobs, :cancelled],
          %{count: 1},
          %{
            job_id: job.id,
            driver_id: job.driver_id,
            provider_id: job.provider_id,
            cancellation_reason: reason
          }
        )

        {:ok, cancelled_job}

      {:error, changeset} ->
        Logger.error("Failed to cancel job",
          job_id: job.id,
          errors: inspect(changeset.errors)
        )

        {:error, changeset}
    end
  end

  # Broadcasting functions using tap/2 pattern

  defp broadcast_job_created({:ok, job}) do
    Logger.info("Job created", %{job_id: job.id, driver_id: job.driver_id})

    TireDispatchWeb.Endpoint.broadcast(
      "jobs:#{job.id}",
      "job_created",
      %{job: job}
    )

    TireDispatchWeb.Endpoint.broadcast(
      "driver:#{job.driver_id}:jobs",
      "job_created",
      %{job: job}
    )

    TireDispatchWeb.Endpoint.broadcast(
      "admin:jobs",
      "job_created",
      %{job: job}
    )

    {:ok, job}
  end

  defp broadcast_job_created(error), do: error

  defp broadcast_job_accepted({:ok, job}) do
    Logger.info("Job accepted", %{
      job_id: job.id,
      provider_id: job.provider_id,
      driver_id: job.driver_id
    })

    TireDispatchWeb.Endpoint.broadcast(
      "jobs:#{job.id}",
      "job_accepted",
      %{job: job}
    )

    TireDispatchWeb.Endpoint.broadcast(
      "driver:#{job.driver_id}:jobs",
      "job_accepted",
      %{job: job}
    )

    TireDispatchWeb.Endpoint.broadcast(
      "provider:#{job.provider_id}:jobs",
      "job_accepted",
      %{job: job}
    )

    TireDispatchWeb.Endpoint.broadcast(
      "admin:jobs",
      "job_accepted",
      %{job: job}
    )

    # Send SMS notification to driver
    send_provider_accepted_notification({:ok, job})

    {:ok, job}
  end

  defp broadcast_job_accepted(error), do: error

  defp broadcast_job_updated({:ok, job}) do
    Logger.info("Job updated", %{job_id: job.id, status: job.status})

    TireDispatchWeb.Endpoint.broadcast(
      "jobs:#{job.id}",
      "job_updated",
      %{job: job}
    )

    TireDispatchWeb.Endpoint.broadcast(
      "driver:#{job.driver_id}:jobs",
      "job_updated",
      %{job: job}
    )

    if job.provider_id do
      TireDispatchWeb.Endpoint.broadcast(
        "provider:#{job.provider_id}:jobs",
        "job_updated",
        %{job: job}
      )
    end

    TireDispatchWeb.Endpoint.broadcast(
      "admin:jobs",
      "job_updated",
      %{job: job}
    )

    {:ok, job}
  end

  defp broadcast_job_updated(error), do: error

  defp broadcast_job_completed({:ok, job}) do
    Logger.info("Job completed", %{
      job_id: job.id,
      provider_id: job.provider_id,
      completed_at: job.completed_at
    })

    TireDispatchWeb.Endpoint.broadcast(
      "jobs:#{job.id}",
      "job_completed",
      %{job: job}
    )

    TireDispatchWeb.Endpoint.broadcast(
      "driver:#{job.driver_id}:jobs",
      "job_completed",
      %{job: job}
    )

    TireDispatchWeb.Endpoint.broadcast(
      "provider:#{job.provider_id}:jobs",
      "job_completed",
      %{job: job}
    )

    TireDispatchWeb.Endpoint.broadcast(
      "admin:jobs",
      "job_completed",
      %{job: job}
    )

    # Send SMS and email notifications to driver
    send_job_completion_notification({:ok, job})

    {:ok, job}
  end

  defp broadcast_job_completed(error), do: error

  defp broadcast_job_cancelled({:ok, job}) do
    Logger.info("Job cancelled", %{
      job_id: job.id,
      reason: job.cancellation_reason
    })

    TireDispatchWeb.Endpoint.broadcast(
      "jobs:#{job.id}",
      "job_cancelled",
      %{job: job}
    )

    TireDispatchWeb.Endpoint.broadcast(
      "driver:#{job.driver_id}:jobs",
      "job_cancelled",
      %{job: job}
    )

    if job.provider_id do
      TireDispatchWeb.Endpoint.broadcast(
        "provider:#{job.provider_id}:jobs",
        "job_cancelled",
        %{job: job}
      )
    end

    TireDispatchWeb.Endpoint.broadcast(
      "admin:jobs",
      "job_cancelled",
      %{job: job}
    )

    {:ok, job}
  end

  defp broadcast_job_cancelled(error), do: error

  @doc """
  Updates the provider's current location for a job.

  This function stores the provider's location as PostGIS geometry and broadcasts
  the update to the driver via PubSub for real-time tracking.

  ## Arguments

    * `job` - The job struct to update
    * `lat` - Provider's current latitude
    * `long` - Provider's current longitude

  ## Returns

    * `{:ok, job}` on success
    * `{:error, changeset}` if validation fails

  ## Examples

      iex> update_provider_location(job, 41.8781, -87.6298)
      {:ok, %Job{provider_location: %Geo.Point{...}}}

  """
  def update_provider_location(%Job{} = job, lat, long) do
    provider_location = %Geo.Point{coordinates: {long, lat}, srid: 4326}

    job
    |> Job.status_changeset(%{provider_location: provider_location})
    |> Repo.update()
    |> tap(&broadcast_provider_location_update/1)
  end

  defp broadcast_provider_location_update({:ok, job}) do
    Logger.debug("Provider location updated", %{
      job_id: job.id,
      provider_id: job.provider_id
    })

    # Extract coordinates for broadcasting
    location_data =
      case job.provider_location do
        %Geo.Point{coordinates: {long, lat}} ->
          %{latitude: lat, longitude: long}

        _ ->
          %{latitude: nil, longitude: nil}
      end

    TireDispatchWeb.Endpoint.broadcast(
      "jobs:#{job.id}",
      "provider_location_update",
      %{job_id: job.id, location: location_data}
    )

    TireDispatchWeb.Endpoint.broadcast(
      "driver:#{job.driver_id}:jobs",
      "provider_location_update",
      %{job_id: job.id, location: location_data}
    )

    {:ok, job}
  end

  defp broadcast_provider_location_update(error), do: error

  # Geographic query functions using PostGIS

  @doc """
  Finds all jobs within a specified radius of a location.

  Uses PostGIS st_distance_sphere function for accurate geographic distance calculations.

  ## Arguments

    * `lat` - Latitude of the center point
    * `long` - Longitude of the center point
    * `radius_km` - Radius in kilometers

  ## Returns

    * List of jobs within the specified radius, ordered by distance (closest first)

  ## Examples

      iex> jobs_within_radius(41.8781, -87.6298, 10)
      [%Job{}, ...]

  """
  def jobs_within_radius(lat, long, radius_km) do
    point = %Geo.Point{coordinates: {long, lat}, srid: 4326}
    radius_meters = radius_km * 1000

    from(j in Job,
      where:
        fragment(
          "ST_DistanceSphere(?, ?) <= ?",
          j.driver_location,
          ^point,
          ^radius_meters
        ),
      order_by:
        fragment(
          "ST_DistanceSphere(?, ?) ASC",
          j.driver_location,
          ^point
        ),
      preload: [:driver]
    )
    |> Repo.all()
  end

  @doc """
  Finds open jobs within a specified radius of a location.

  This is useful for providers to see available jobs near them.

  ## Arguments

    * `lat` - Latitude of the center point
    * `long` - Longitude of the center point
    * `radius_km` - Radius in kilometers

  ## Returns

    * List of open jobs within the specified radius, ordered by distance

  ## Examples

      iex> open_jobs_within_radius(41.8781, -87.6298, 10)
      [%Job{status: :open}, ...]

  """
  def open_jobs_within_radius(lat, long, radius_km) do
    point = %Geo.Point{coordinates: {long, lat}, srid: 4326}
    radius_meters = radius_km * 1000

    from(j in Job,
      where: j.status == :open,
      where:
        fragment(
          "ST_DistanceSphere(?, ?) <= ?",
          j.driver_location,
          ^point,
          ^radius_meters
        ),
      order_by:
        fragment(
          "ST_DistanceSphere(?, ?) ASC",
          j.driver_location,
          ^point
        ),
      preload: [:driver]
    )
    |> Repo.all()
  end

  @doc """
  Calculates the distance in meters between two geographic points.

  Uses PostGIS st_distance_sphere for accurate calculations.

  ## Arguments

    * `point1` - First Geo.Point struct
    * `point2` - Second Geo.Point struct

  ## Returns

    * Distance in meters as a float

  ## Examples

      iex> calculate_distance(
        %Geo.Point{coordinates: {-87.6298, 41.8781}, srid: 4326},
        %Geo.Point{coordinates: {-87.6500, 41.8900}, srid: 4326}
      )
      2543.7

  """
  def calculate_distance(%Geo.Point{} = point1, %Geo.Point{} = point2) do
    query =
      from(j in Job,
        select:
          fragment(
            "ST_DistanceSphere(?, ?)",
            ^point1,
            ^point2
          ),
        limit: 1
      )

    case Repo.one(query) do
      nil -> 0.0
      distance -> distance
    end
  end

  @doc """
  Calculates the distance in meters between a job's driver location and a given point.

  ## Arguments

    * `job` - Job struct with driver_location
    * `lat` - Latitude of the comparison point
    * `long` - Longitude of the comparison point

  ## Returns

    * Distance in meters as a float

  ## Examples

      iex> calculate_job_distance(job, 41.8781, -87.6298)
      1234.5

  """
  def calculate_job_distance(%Job{driver_location: driver_location}, lat, long) do
    point = %Geo.Point{coordinates: {long, lat}, srid: 4326}
    calculate_distance(driver_location, point)
  end

  @doc """
  Lists jobs with geographic and status filters.

  Supports filtering by:
  - Status
  - Date range
  - Geographic region (within radius of a point)

  ## Arguments

    * `filters` - Keyword list of filters

  ## Filter Options

    * `:status` - Filter by job status
    * `:date_range` - Tuple of {start_date, end_date}
    * `:region` - Tuple of {lat, long, radius_km}

  ## Examples

      iex> list_jobs_with_filters(
        status: :completed,
        date_range: {~U[2024-01-01 00:00:00Z], ~U[2024-01-31 23:59:59Z]},
        region: {41.8781, -87.6298, 50}
      )
      [%Job{}, ...]

  """
  def list_jobs_with_filters(filters \\ []) do
    Job
    |> apply_geographic_filters(filters)
    |> apply_filters(filters)
    |> order_by([j], desc: j.inserted_at)
    |> preload([:driver, :provider])
    |> Repo.all()
  end

  # Private helper to apply geographic filters
  defp apply_geographic_filters(query, filters) do
    case Keyword.get(filters, :region) do
      {lat, long, radius_km} ->
        point = %Geo.Point{coordinates: {long, lat}, srid: 4326}
        radius_meters = radius_km * 1000

        from(j in query,
          where:
            fragment(
              "ST_DistanceSphere(?, ?) <= ?",
              j.driver_location,
              ^point,
              ^radius_meters
            ),
          order_by:
            fragment(
              "ST_DistanceSphere(?, ?) ASC",
              j.driver_location,
              ^point
            )
        )

      _ ->
        query
    end
  end

  # Notification helper functions

  defp send_payment_confirmation_notification({:ok, job}) do
    # Preload driver to get phone number and email
    job = Repo.preload(job, :driver)

    # Send SMS notification
    if job.driver.phone_number do
      message = """
      Payment confirmed for Job ##{String.slice(job.id, 0..7)}!

      Your #{format_service_type(job.service_type)} service request has been received.
      A provider will be assigned shortly.

      - Tire Dispatch
      """

      TireDispatch.Notifications.send_sms(
        job.driver.phone_number,
        message,
        job_id: job.id
      )
    end

    # Send email notification
    if job.driver.email do
      TireDispatch.Notifications.send_payment_confirmation_email(
        job.driver.email,
        job,
        job.estimated_price_cents
      )
    end

    {:ok, job}
  end

  defp send_payment_confirmation_notification(error), do: error

  defp send_provider_accepted_notification({:ok, job}) do
    # Preload driver and provider to get contact info
    job = Repo.preload(job, [:driver, :provider])

    # Send SMS notification to driver
    if job.driver.phone_number && job.provider do
      message = """
      Great news! Your tire service has been accepted.

      Provider: #{job.provider.email}
      Job: ##{String.slice(job.id, 0..7)}
      Service: #{format_service_type(job.service_type)}

      Your provider will be on the way soon!

      - Tire Dispatch
      """

      TireDispatch.Notifications.send_sms(
        job.driver.phone_number,
        message,
        job_id: job.id
      )
    end

    {:ok, job}
  end

  defp send_provider_accepted_notification(error), do: error

  defp send_job_completion_notification({:ok, job}) do
    # Preload driver to get contact info
    job = Repo.preload(job, :driver)

    # Send SMS notification
    if job.driver.phone_number do
      message = """
      Your tire service is complete!

      Job ##{job.id}
      Service: #{format_service_type(job.service_type)}
      Amount: #{format_currency(job.final_price_cents)}

      Check your email for the full receipt with before/after photos.

      Thank you for using Tire Dispatch!
      """

      TireDispatch.Notifications.send_sms(
        job.driver.phone_number,
        message,
        job_id: job.id
      )
    end

    # Send email notification with receipt
    if job.driver.email do
      receipt_data = %{
        amount_cents: job.final_price_cents,
        receipt_url: "https://tiredispatch.com/receipts/#{job.id}"
      }

      TireDispatch.Notifications.send_job_completion_email(
        job.driver.email,
        job,
        receipt_data
      )
    end

    {:ok, job}
  end

  defp send_job_completion_notification(error), do: error

  # Helper functions for formatting

  defp format_service_type(service_type) do
    service_type
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp format_currency(amount_cents) do
    dollars = amount_cents / 100
    "$#{:erlang.float_to_binary(dollars, decimals: 2)}"
  end
end
