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

    %Job{}
    |> Job.changeset(attrs)
    |> Repo.insert()
    |> tap(&broadcast_job_created/1)
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
    job
    |> Job.status_changeset(%{status: :accepted, provider_id: provider_id})
    |> Repo.update()
    |> tap(&broadcast_job_accepted/1)
  end

  def accept_job(%Job{} = _job, _provider_id) do
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
    job
    |> Job.status_changeset(%{status: :en_route})
    |> Repo.update()
    |> tap(&broadcast_job_updated/1)
  end

  def start_travel(%Job{} = _job) do
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
    job
    |> Job.status_changeset(%{status: :on_site})
    |> Repo.update()
    |> tap(&broadcast_job_updated/1)
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
  end

  def complete_job(%Job{} = _job, _before_photo_url, _after_photo_url) do
    {:error, "Job can only be completed from on_site status"}
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
  def cancel_job(%Job{status: :completed} = _job, _reason) do
    {:error, "Cannot cancel a completed job"}
  end

  def cancel_job(%Job{} = job, reason) do
    job
    |> Job.status_changeset(%{status: :cancelled})
    |> Ecto.Changeset.put_change(:cancellation_reason, reason)
    |> Repo.update()
    |> tap(&broadcast_job_cancelled/1)
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
          "ST_Distance_Sphere(?, ?) <= ?",
          j.driver_location,
          ^point,
          ^radius_meters
        ),
      order_by:
        fragment(
          "ST_Distance_Sphere(?, ?) ASC",
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
          "ST_Distance_Sphere(?, ?) <= ?",
          j.driver_location,
          ^point,
          ^radius_meters
        ),
      order_by:
        fragment(
          "ST_Distance_Sphere(?, ?) ASC",
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
            "ST_Distance_Sphere(?, ?)",
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
              "ST_Distance_Sphere(?, ?) <= ?",
              j.driver_location,
              ^point,
              ^radius_meters
            ),
          order_by:
            fragment(
              "ST_Distance_Sphere(?, ?) ASC",
              j.driver_location,
              ^point
            )
        )

      _ ->
        query
    end
  end
end
