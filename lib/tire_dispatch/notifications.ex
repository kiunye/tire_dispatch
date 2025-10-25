defmodule TireDispatch.Notifications do
  @moduledoc """
  The Notifications context.

  Handles sending SMS and email notifications for job events.
  Enqueues notifications via Oban workers for async processing with retry logic.
  """

  require Logger

  alias TireDispatch.Mailer
  alias TireDispatch.Notifications.AfricasTalking
  alias TireDispatch.Notifications.Email
  alias TireDispatch.Workers.SendNotificationWorker

  @doc """
  Sends an SMS notification.

  ## Arguments

    * `to` - Phone number in E.164 format
    * `message` - SMS message content
    * `opts` - Optional keyword list with:
      * `:async` - If true, enqueue via Oban (default: true)
      * `:job_id` - Associated job ID for logging

  ## Returns

    * `{:ok, result}` - Success with message ID
    * `{:error, reason}` - Failure

  ## Examples

      iex> send_sms("+254712345678", "Your provider is on the way!")
      {:ok, %{message_id: "ATXid_abc123"}}

      iex> send_sms("+254712345678", "Urgent message", async: false)
      {:ok, %{message_id: "ATXid_xyz789"}}
  """
  def send_sms(to, message, opts \\ []) do
    async = Keyword.get(opts, :async, true)
    job_id = Keyword.get(opts, :job_id)

    if async do
      enqueue_sms(to, message, job_id)
    else
      send_sms_now(to, message, job_id)
    end
  end

  @doc """
  Sends an email notification.

  ## Arguments

    * `to` - Recipient email address
    * `subject` - Email subject
    * `body` - Email body (HTML or text)
    * `opts` - Optional keyword list with:
      * `:async` - If true, enqueue via Oban (default: true)
      * `:job_id` - Associated job ID for logging
      * `:email_type` - Type of email (for template selection)

  ## Returns

    * `{:ok, result}` - Success
    * `{:error, reason}` - Failure

  ## Examples

      iex> send_email("driver@example.com", "Job Complete", "Your service is complete!")
      {:ok, %{id: "email_123"}}
  """
  def send_email(to, subject, body, opts \\ []) do
    async = Keyword.get(opts, :async, true)
    job_id = Keyword.get(opts, :job_id)

    if async do
      enqueue_email(to, subject, body, job_id)
    else
      send_email_now(to, subject, body, job_id)
    end
  end

  @doc """
  Sends a job completion email with receipt and photos.

  ## Arguments

    * `to` - Recipient email address
    * `job` - Job struct with completion details
    * `receipt_data` - Map with receipt information
    * `opts` - Optional keyword list with `:async` (default: true)

  ## Returns

    * `{:ok, result}` - Success
    * `{:error, reason}` - Failure
  """
  def send_job_completion_email(to, job, receipt_data, opts \\ []) do
    async = Keyword.get(opts, :async, true)

    email = Email.job_completion_email(to, job, receipt_data)

    if async do
      enqueue_email_struct(email, job.id)
    else
      send_email_struct_now(email, job.id)
    end
  end

  @doc """
  Sends a payment confirmation email.

  ## Arguments

    * `to` - Recipient email address
    * `job` - Job struct
    * `amount` - Payment amount in cents
    * `opts` - Optional keyword list with `:async` (default: true)

  ## Returns

    * `{:ok, result}` - Success
    * `{:error, reason}` - Failure
  """
  def send_payment_confirmation_email(to, job, amount, opts \\ []) do
    async = Keyword.get(opts, :async, true)

    email = Email.payment_confirmation_email(to, job, amount)

    if async do
      enqueue_email_struct(email, job.id)
    else
      send_email_struct_now(email, job.id)
    end
  end

  @doc """
  Sends a refund confirmation email.

  ## Arguments

    * `to` - Recipient email address
    * `job` - Job struct
    * `amount` - Refund amount in cents
    * `reason` - Refund reason
    * `opts` - Optional keyword list with `:async` (default: true)

  ## Returns

    * `{:ok, result}` - Success
    * `{:error, reason}` - Failure
  """
  def send_refund_confirmation_email(to, job, amount, reason, opts \\ []) do
    async = Keyword.get(opts, :async, true)

    email = Email.refund_confirmation_email(to, job, amount, reason)

    if async do
      enqueue_email_struct(email, job.id)
    else
      send_email_struct_now(email, job.id)
    end
  end

  @doc """
  Sends a subscription update email.

  ## Arguments

    * `to` - Recipient email address
    * `provider` - Provider struct
    * `tier` - Subscription tier (:premium or :standard)
    * `opts` - Optional keyword list with `:async` (default: true)

  ## Returns

    * `{:ok, result}` - Success
    * `{:error, reason}` - Failure
  """
  def send_subscription_update_email(to, provider, tier, opts \\ []) do
    async = Keyword.get(opts, :async, true)

    email = Email.subscription_update_email(to, provider, tier)

    if async do
      enqueue_email_struct(email, nil)
    else
      send_email_struct_now(email, nil)
    end
  end

  # Private functions - SMS

  defp send_sms_now(to, message, job_id) do
    Logger.info(
      "Sending SMS: to=#{to}, job_id=#{job_id}, message_length=#{String.length(message)}"
    )

    case AfricasTalking.send_sms(to, message) do
      {:ok, result} ->
        Logger.info(
          "SMS sent successfully: to=#{to}, job_id=#{job_id}, message_id=#{result.message_id}, cost=#{result.cost}"
        )

        {:ok, result}

      {:error, reason} = error ->
        Logger.error("SMS send failed: to=#{to}, job_id=#{job_id}, reason=#{inspect(reason)}")

        error
    end
  end

  defp enqueue_sms(to, message, job_id) do
    %{
      type: "sms",
      to: to,
      message: message,
      job_id: job_id
    }
    |> SendNotificationWorker.new(queue: :notifications)
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        Logger.info("SMS notification enqueued: to=#{to}, job_id=#{job_id}")

        {:ok, :enqueued}

      {:error, reason} = error ->
        Logger.error(
          "Failed to enqueue SMS notification: to=#{to}, job_id=#{job_id}, reason=#{inspect(reason)}"
        )

        error
    end
  end

  # Private functions - Email

  defp send_email_now(to, subject, body, job_id) do
    Logger.info("Sending email: to=#{to}, subject=#{subject}, job_id=#{job_id}")

    email =
      Swoosh.Email.new()
      |> Swoosh.Email.to(to)
      |> Swoosh.Email.from({"Tire Dispatch", "noreply@tiredispatch.com"})
      |> Swoosh.Email.subject(subject)
      |> Swoosh.Email.html_body(body)

    case Mailer.deliver(email) do
      {:ok, result} ->
        Logger.info("Email sent successfully: to=#{to}, subject=#{subject}, job_id=#{job_id}")

        {:ok, result}

      {:error, reason} = error ->
        Logger.error(
          "Email send failed: to=#{to}, subject=#{subject}, job_id=#{job_id}, reason=#{inspect(reason)}"
        )

        error
    end
  end

  defp enqueue_email(to, subject, body, job_id) do
    %{
      type: "email",
      to: to,
      subject: subject,
      body: body,
      job_id: job_id
    }
    |> SendNotificationWorker.new(queue: :notifications)
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        Logger.info("Email notification enqueued: to=#{to}, subject=#{subject}, job_id=#{job_id}")

        {:ok, :enqueued}

      {:error, reason} = error ->
        Logger.error(
          "Failed to enqueue email notification: to=#{to}, subject=#{subject}, job_id=#{job_id}, reason=#{inspect(reason)}"
        )

        error
    end
  end

  defp send_email_struct_now(email, job_id) do
    Logger.info(
      "Sending email from struct: to=#{inspect(email.to)}, subject=#{email.subject}, job_id=#{job_id}"
    )

    case Mailer.deliver(email) do
      {:ok, result} ->
        Logger.info(
          "Email sent successfully: to=#{inspect(email.to)}, subject=#{email.subject}, job_id=#{job_id}"
        )

        {:ok, result}

      {:error, reason} = error ->
        Logger.error(
          "Email send failed: to=#{inspect(email.to)}, subject=#{email.subject}, job_id=#{job_id}, reason=#{inspect(reason)}"
        )

        error
    end
  end

  defp enqueue_email_struct(email, job_id) do
    # Normalize email addresses to strings for JSON serialization
    to_addresses = normalize_email_addresses(email.to)
    from_address = normalize_email_address(email.from)

    %{
      type: "email_struct",
      email: %{
        to: to_addresses,
        from: from_address,
        subject: email.subject,
        html_body: email.html_body,
        text_body: email.text_body
      },
      job_id: job_id
    }
    |> SendNotificationWorker.new(queue: :notifications)
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        Logger.info(
          "Email notification enqueued: to=#{inspect(to_addresses)}, subject=#{email.subject}, job_id=#{job_id}"
        )

        {:ok, :enqueued}

      {:error, reason} = error ->
        Logger.error(
          "Failed to enqueue email notification: to=#{inspect(to_addresses)}, subject=#{email.subject}, job_id=#{job_id}, reason=#{inspect(reason)}"
        )

        error
    end
  end

  # Helper to normalize email addresses for JSON serialization
  defp normalize_email_addresses(addresses) when is_list(addresses) do
    Enum.map(addresses, &normalize_email_address/1)
  end

  defp normalize_email_addresses(address), do: [normalize_email_address(address)]

  defp normalize_email_address({_name, email}) when is_binary(email), do: email
  defp normalize_email_address(email) when is_binary(email), do: email
  defp normalize_email_address(_), do: nil
end
