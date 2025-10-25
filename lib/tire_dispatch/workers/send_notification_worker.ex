defmodule TireDispatch.Workers.SendNotificationWorker do
  @moduledoc """
  Oban worker that handles sending SMS and email notifications.

  Supports:
  - SMS notifications via Twilio (using Req for direct API calls)
  - Email notifications via Swoosh
  - Automatic retry with exponential backoff on failure

  Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 10.6, 11.3
  """

  use Oban.Worker,
    queue: :notifications,
    max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "sms"} = args}) do
    send_sms_africas_talking(args["to"], args["message"], args["job_id"])
  end

  def perform(%Oban.Job{args: %{"type" => "email"} = args}) do
    send_email(args["to"], args["subject"], args["body"] || args["message"], args["job_id"])
  end

  def perform(%Oban.Job{args: %{"type" => "email_struct"} = args}) do
    send_email_from_struct(args["email"], args["job_id"])
  end

  def perform(%Oban.Job{args: args}) do
    Logger.error("Invalid notification job args", args: inspect(args))
    {:error, :invalid_args}
  end

  @doc """
  Sends an SMS notification via AfricasTalking API.

  ## Arguments

    * `to` - Phone number to send SMS to (E.164 format)
    * `message` - Message body
    * `job_id` - Associated job ID for logging

  ## Returns

    * `:ok` on success
    * `{:error, reason}` on failure
  """
  def send_sms_africas_talking(to, message, job_id) do
    Logger.info(
      "Sending SMS notification via AfricasTalking: to=#{to}, message_length=#{String.length(message)}, job_id=#{job_id}"
    )

    case TireDispatch.Notifications.AfricasTalking.send_sms(to, message) do
      {:ok, result} ->
        Logger.info(
          "SMS sent successfully via AfricasTalking: to=#{to}, job_id=#{job_id}, message_id=#{result.message_id}, cost=#{result.cost}"
        )

        :ok

      {:error, reason} ->
        Logger.error(
          "Failed to send SMS via AfricasTalking: to=#{to}, job_id=#{job_id}, reason=#{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @doc """
  Sends an SMS notification via Twilio API (legacy support).

  ## Arguments

    * `to` - Phone number to send SMS to (E.164 format)
    * `message` - Message body

  ## Returns

    * `:ok` on success
    * `{:error, reason}` on failure
  """
  def send_sms(to, message) do
    Logger.info("Sending SMS notification", to: to, message_length: String.length(message))

    # Get Twilio credentials from environment
    account_sid = System.get_env("TWILIO_ACCOUNT_SID")
    auth_token = System.get_env("TWILIO_AUTH_TOKEN")
    from_number = System.get_env("TWILIO_PHONE_NUMBER")

    if is_nil(account_sid) or is_nil(auth_token) or is_nil(from_number) do
      Logger.warning("Twilio credentials not configured, skipping SMS send")
      # In development, we'll just log and return success
      # In production, this should return an error
      :ok
    else
      send_twilio_sms(account_sid, auth_token, from_number, to, message)
    end
  end

  defp send_twilio_sms(account_sid, auth_token, from_number, to, message) do
    url = "https://api.twilio.com/2010-04-01/Accounts/#{account_sid}/Messages.json"

    auth = Base.encode64("#{account_sid}:#{auth_token}")

    headers = [
      {"Authorization", "Basic #{auth}"},
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]

    body =
      URI.encode_query(%{
        "From" => from_number,
        "To" => to,
        "Body" => message
      })

    case Req.post(url, headers: headers, body: body) do
      {:ok, %{status: status, body: response_body}} when status in 200..299 ->
        Logger.info("SMS sent successfully",
          to: to,
          message_sid: response_body["sid"]
        )

        :ok

      {:ok, %{status: status, body: body}} ->
        Logger.error("Twilio API error",
          status: status,
          error: inspect(body)
        )

        {:error, "Twilio API returned status #{status}"}

      {:error, reason} ->
        Logger.error("Failed to send SMS",
          to: to,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  @doc """
  Sends an email notification via Swoosh.

  ## Arguments

    * `to` - Email address to send to
    * `subject` - Email subject line
    * `message` - Email body (HTML or plain text)
    * `job_id` - Associated job ID for logging

  ## Returns

    * `:ok` on success
    * `{:error, reason}` on failure
  """
  def send_email(to, subject, message, job_id \\ nil) do
    Logger.info("Sending email notification", to: to, subject: subject, job_id: job_id)

    # Build email using Swoosh
    email =
      Swoosh.Email.new()
      |> Swoosh.Email.to(to)
      |> Swoosh.Email.from({"Tire Dispatch", get_from_email()})
      |> Swoosh.Email.subject(subject)
      |> Swoosh.Email.html_body(message)

    # Send email via configured mailer
    case TireDispatch.Mailer.deliver(email) do
      {:ok, _metadata} ->
        Logger.info("Email sent successfully", to: to, subject: subject, job_id: job_id)
        :ok

      {:error, reason} ->
        Logger.error("Failed to send email",
          to: to,
          subject: subject,
          job_id: job_id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  @doc """
  Sends an email from a pre-built email struct.

  ## Arguments

    * `email_data` - Map with email fields (to, from, subject, html_body, text_body)
    * `job_id` - Associated job ID for logging

  ## Returns

    * `:ok` on success
    * `{:error, reason}` on failure
  """
  def send_email_from_struct(email_data, job_id) do
    Logger.info("Sending email from struct",
      to: email_data["to"],
      subject: email_data["subject"],
      job_id: job_id
    )

    # Build email using Swoosh
    email =
      Swoosh.Email.new()
      |> Swoosh.Email.to(email_data["to"])
      |> Swoosh.Email.from(email_data["from"])
      |> Swoosh.Email.subject(email_data["subject"])
      |> Swoosh.Email.html_body(email_data["html_body"])

    email =
      if email_data["text_body"] do
        Swoosh.Email.text_body(email, email_data["text_body"])
      else
        email
      end

    # Send email via configured mailer
    case TireDispatch.Mailer.deliver(email) do
      {:ok, _metadata} ->
        Logger.info("Email sent successfully",
          to: email_data["to"],
          subject: email_data["subject"],
          job_id: job_id
        )

        :ok

      {:error, reason} ->
        Logger.error("Failed to send email",
          to: email_data["to"],
          subject: email_data["subject"],
          job_id: job_id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp get_from_email do
    System.get_env("FROM_EMAIL") || "noreply@tiredispatch.com"
  end

  @doc """
  Enqueues an SMS notification job.

  ## Arguments

    * `to` - Phone number to send SMS to
    * `message` - Message body

  ## Returns

    * `{:ok, job}` on success
    * `{:error, changeset}` on failure
  """
  def enqueue_sms(to, message) do
    %{
      type: "sms",
      to: to,
      message: message
    }
    |> new()
    |> Oban.insert()
  end

  @doc """
  Enqueues an email notification job.

  ## Arguments

    * `to` - Email address to send to
    * `subject` - Email subject line
    * `message` - Email body

  ## Returns

    * `{:ok, job}` on success
    * `{:error, changeset}` on failure
  """
  def enqueue_email(to, subject, message) do
    %{
      type: "email",
      to: to,
      subject: subject,
      message: message
    }
    |> new()
    |> Oban.insert()
  end
end
