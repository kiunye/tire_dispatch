defmodule TireDispatchWeb.JobChannel do
  @moduledoc """
  Phoenix Channel for real-time job communication.

  This channel handles bidirectional communication for job-specific events:
  - Real-time location updates from providers
  - Job completion notifications
  - Status updates

  Only the job's driver and provider can join the channel for security.
  """

  use TireDispatchWeb, :channel

  alias TireDispatch.Jobs

  require Logger

  @doc """
  Authorizes a user to join a job channel.

  Only the driver who created the job or the provider assigned to the job
  can join the channel. This ensures privacy and security of job communications.

  ## Parameters

    * `"jobs:" <> job_id` - The channel topic with job ID
    * `_payload` - Join payload (not currently used)
    * `socket` - The socket with user_id in assigns

  ## Returns

    * `{:ok, socket}` if authorized
    * `{:error, %{reason: "unauthorized"}}` if not authorized

  ## Examples

      # Driver joining their own job
      {:ok, socket} = join("jobs:123", %{}, socket)

      # Provider joining assigned job
      {:ok, socket} = join("jobs:123", %{}, socket)

      # Unauthorized user
      {:error, %{reason: "unauthorized"}} = join("jobs:123", %{}, socket)

  """
  @impl true
  def join("jobs:" <> job_id_string, _payload, socket) do
    user_id = socket.assigns.user_id

    # Convert job_id from string to integer
    job_id =
      case Integer.parse(job_id_string) do
        {id, ""} -> id
        _ -> job_id_string
      end

    case Jobs.get_job(job_id) do
      {:ok, job} ->
        if authorized?(job, user_id) do
          Logger.info("User joined job channel", %{
            user_id: user_id,
            job_id: job_id
          })

          {:ok, assign(socket, :job_id, job_id)}
        else
          Logger.warning("Unauthorized job channel join attempt", %{
            user_id: user_id,
            job_id: job_id
          })

          {:error, %{reason: "unauthorized"}}
        end

      {:error, :not_found} ->
        Logger.warning("Job channel join failed - job not found", %{
          user_id: user_id,
          job_id: job_id
        })

        {:error, %{reason: "job_not_found"}}
    end
  end

  @doc """
  Handles incoming messages from channel clients.

  Supports the following events:

  ## "update_location"

  Providers send GPS coordinates for real-time tracking. The location is stored
  in the job record and broadcast to all channel subscribers (driver and provider).

  Parameters:
    * `%{"latitude" => lat, "longitude" => long}` - GPS coordinates

  ## "complete_job"

  Providers mark the job as complete by providing before and after photo URLs.
  This triggers job completion, broadcasts to all parties, and initiates payout processing.

  Parameters:
    * `%{"before_photo_url" => url1, "after_photo_url" => url2}` - Photo URLs

  ## Returns

    * `{:reply, :ok, socket}` on success
    * `{:reply, {:error, %{reason: String.t()}}, socket}` on failure
  """
  @impl true
  def handle_in("update_location", %{"latitude" => lat, "longitude" => long}, socket)
      when is_number(lat) and is_number(long) do
    job_id = socket.assigns.job_id

    case Jobs.get_job(job_id) do
      {:ok, job} ->
        case Jobs.update_provider_location(job, lat, long) do
          {:ok, _updated_job} ->
            Logger.info("Provider location updated via channel", %{
              job_id: job_id,
              provider_id: job.provider_id,
              latitude: lat,
              longitude: long
            })

            # Broadcast to all channel subscribers (driver and provider)
            broadcast!(socket, "provider_location_update", %{
              job_id: job_id,
              location: %{latitude: lat, longitude: long}
            })

            {:reply, :ok, socket}

          {:error, changeset} ->
            Logger.error("Failed to update provider location", %{
              job_id: job_id,
              errors: inspect(changeset.errors)
            })

            {:reply, {:error, %{reason: "Failed to update location"}}, socket}
        end

      {:error, :not_found} ->
        Logger.error("Job not found for location update", %{job_id: job_id})
        {:reply, {:error, %{reason: "Job not found"}}, socket}
    end
  end

  @impl true
  def handle_in("update_location", params, socket) do
    Logger.error("Invalid location update params", %{
      job_id: socket.assigns.job_id,
      params: inspect(params)
    })

    {:reply, {:error, %{reason: "Invalid location parameters"}}, socket}
  end

  @impl true
  def handle_in(
        "complete_job",
        %{"before_photo_url" => before_url, "after_photo_url" => after_url},
        socket
      )
      when is_binary(before_url) and is_binary(after_url) do
    job_id = socket.assigns.job_id

    case Jobs.get_job(job_id) do
      {:ok, job} ->
        case Jobs.complete_job(job, before_url, after_url) do
          {:ok, completed_job} ->
            Logger.info("Job completed via channel", %{
              job_id: job_id,
              provider_id: job.provider_id,
              driver_id: job.driver_id,
              completed_at: completed_job.completed_at
            })

            # Broadcast completion to all channel subscribers
            broadcast!(socket, "job_completed", %{
              job_id: job_id,
              job: %{
                id: completed_job.id,
                status: completed_job.status,
                completed_at: completed_job.completed_at,
                before_photo_url: completed_job.before_photo_url,
                after_photo_url: completed_job.after_photo_url,
                final_price_cents: completed_job.final_price_cents
              }
            })

            # Also broadcast to admin channel
            TireDispatchWeb.Endpoint.broadcast(
              "admin:jobs",
              "job_completed",
              %{job: completed_job}
            )

            {:reply, :ok, socket}

          {:error, reason} when is_binary(reason) ->
            Logger.error("Failed to complete job via channel", %{
              job_id: job_id,
              reason: reason
            })

            {:reply, {:error, %{reason: reason}}, socket}

          {:error, changeset} ->
            Logger.error("Failed to complete job via channel", %{
              job_id: job_id,
              errors: inspect(changeset.errors)
            })

            {:reply, {:error, %{reason: "Failed to complete job"}}, socket}
        end

      {:error, :not_found} ->
        Logger.error("Job not found for completion", %{job_id: job_id})
        {:reply, {:error, %{reason: "Job not found"}}, socket}
    end
  end

  @impl true
  def handle_in("complete_job", params, socket) do
    Logger.error("Invalid complete_job params", %{
      job_id: socket.assigns.job_id,
      params: inspect(params)
    })

    {:reply, {:error, %{reason: "Missing required photo URLs"}}, socket}
  end

  # Private helper to check if user is authorized to access the job
  defp authorized?(job, user_id) do
    # User is authorized if they are the driver or the assigned provider
    job.driver_id == user_id || job.provider_id == user_id
  end
end
