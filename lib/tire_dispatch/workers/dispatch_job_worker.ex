defmodule TireDispatch.Workers.DispatchJobWorker do
  @moduledoc """
  Oban worker that dispatches new jobs to available providers.

  Responsibilities:
  - Broadcast new jobs to providers within service radius
  - Send push notifications to provider apps
  - Calculate provider eligibility based on location and availability

  Requirements: 2.4, 11.3
  """

  use Oban.Worker, queue: :default

  import Ecto.Query
  alias TireDispatch.Jobs
  alias TireDispatch.Jobs.Job
  alias TireDispatch.Providers
  alias TireDispatch.Repo
  alias TireDispatch.Workers.SendNotificationWorker
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"job_id" => job_id}}) do
    Logger.info("Dispatching job to providers", job_id: job_id)

    with {:ok, job} <- Jobs.get_job(job_id),
         :ok <- validate_job_for_dispatch(job),
         {:ok, providers} <- find_eligible_providers(job) do
      # Broadcast to each provider
      Enum.each(providers, fn provider ->
        broadcast_to_provider(job, provider)
        send_notification_to_provider(job, provider)
      end)

      Logger.info("Job dispatched to #{length(providers)} providers",
        job_id: job_id,
        provider_count: length(providers)
      )

      :ok
    else
      {:error, reason} = error ->
        Logger.error("Failed to dispatch job",
          job_id: job_id,
          reason: inspect(reason)
        )

        error
    end
  end

  def perform(%Oban.Job{args: args}) do
    Logger.error("Invalid dispatch job args", args: inspect(args))
    {:error, :invalid_args}
  end

  @doc """
  Enqueues a job dispatch worker.

  ## Arguments

    * `job_id` - UUID of the job to dispatch

  ## Returns

    * `{:ok, oban_job}` on success
    * `{:error, changeset}` on failure
  """
  def enqueue_dispatch(job_id) do
    %{job_id: job_id}
    |> new()
    |> Oban.insert()
  end

  defp validate_job_for_dispatch(job) do
    cond do
      job.status != :open ->
        {:error, :job_not_open}

      is_nil(job.driver_location) ->
        {:error, :missing_driver_location}

      true ->
        :ok
    end
  end

  defp find_eligible_providers(job) do
    # Extract coordinates from PostGIS geometry
    driver_coords = extract_coordinates(job.driver_location)

    if is_nil(driver_coords) do
      {:error, :invalid_driver_location}
    else
      {lat, lng} = driver_coords

      # Find providers within radius using PostGIS
      providers =
        Providers.list_providers_within_radius(lat, lng, get_search_radius())
        |> filter_by_vehicle_type(job.vehicle_type)
        |> filter_by_availability()

      {:ok, providers}
    end
  end

  defp extract_coordinates(%Geo.Point{coordinates: {lng, lat}}), do: {lat, lng}
  defp extract_coordinates(_), do: nil

  defp get_search_radius do
    # Default search radius in kilometers
    # Could be made configurable per job urgency
    50
  end

  defp filter_by_vehicle_type(providers, job_vehicle_type) do
    # Filter providers who can service the vehicle type
    # For now, we assume all providers can service all vehicle types
    # In production, you'd filter based on provider.vehicle_type
    Enum.filter(providers, fn provider ->
      # Provider vehicle type should be equal or larger than job vehicle type
      can_service_vehicle?(provider.vehicle_type, job_vehicle_type)
    end)
  end

  defp can_service_vehicle?(provider_vehicle, job_vehicle) do
    # Vehicle type hierarchy: compact < suv < truck
    # A truck provider can service all types
    # An SUV provider can service compact and suv
    # A compact provider can only service compact
    vehicle_hierarchy = %{
      compact: 1,
      suv: 2,
      truck: 3
    }

    provider_level = Map.get(vehicle_hierarchy, provider_vehicle, 0)
    job_level = Map.get(vehicle_hierarchy, job_vehicle, 0)

    provider_level >= job_level
  end

  defp filter_by_availability(providers) do
    # Filter providers who are currently available
    # For now, we check if they have an active job
    provider_ids = Enum.map(providers, & &1.id)

    active_provider_ids =
      from(j in Job,
        where:
          j.provider_id in ^provider_ids and
            j.status in [:accepted, :en_route, :on_site],
        select: j.provider_id,
        distinct: true
      )
      |> Repo.all()

    # Return providers who don't have active jobs
    Enum.reject(providers, fn provider ->
      provider.id in active_provider_ids
    end)
  end

  defp broadcast_to_provider(job, provider) do
    # Broadcast to provider's personal topic
    topic = "provider:#{provider.id}:jobs"

    TireDispatchWeb.Endpoint.broadcast(topic, "new_job_available", %{
      job_id: job.id,
      service_type: job.service_type,
      urgency_tier: job.urgency_tier,
      vehicle_type: job.vehicle_type,
      estimated_price_cents: job.estimated_price_cents,
      driver_location: format_location(job.driver_location),
      issue_notes: job.issue_notes
    })

    Logger.debug("Broadcasted job to provider",
      job_id: job.id,
      provider_id: provider.id,
      topic: topic
    )
  end

  defp send_notification_to_provider(job, provider) do
    # Get provider's user to access phone number
    case Repo.preload(provider, :user) do
      %{user: user} when not is_nil(user) ->
        message = format_notification_message(job)

        # Enqueue SMS notification
        case SendNotificationWorker.enqueue_sms(user.phone_number, message) do
          {:ok, _oban_job} ->
            Logger.debug("Notification queued for provider",
              job_id: job.id,
              provider_id: provider.id
            )

          {:error, reason} ->
            Logger.error("Failed to queue notification",
              job_id: job.id,
              provider_id: provider.id,
              reason: inspect(reason)
            )
        end

      _ ->
        Logger.warning("Provider has no associated user",
          provider_id: provider.id
        )
    end
  end

  defp format_location(%Geo.Point{coordinates: {lng, lat}}) do
    %{latitude: lat, longitude: lng}
  end

  defp format_location(_), do: nil

  defp format_notification_message(job) do
    service_name = format_service_type(job.service_type)
    urgency = format_urgency(job.urgency_tier)

    "New #{urgency} tire service request: #{service_name}. " <>
      "Estimated pay: $#{div(job.estimated_price_cents, 100)}. " <>
      "Open your app to accept."
  end

  defp format_service_type(:flat_repair), do: "Flat Tire Repair"
  defp format_service_type(:nail_removal), do: "Nail Removal"
  defp format_service_type(:air_fill), do: "Tire Air Fill"
  defp format_service_type(:new_tire), do: "New Tire Installation"
  defp format_service_type(:replacement), do: "Tire Replacement"
  defp format_service_type(_), do: "Tire Service"

  defp format_urgency(:emergency), do: "EMERGENCY"
  defp format_urgency(:rush), do: "RUSH"
  defp format_urgency(:standard), do: "standard"
end
