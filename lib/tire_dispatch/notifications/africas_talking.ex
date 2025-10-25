defmodule TireDispatch.Notifications.AfricasTalking do
  @moduledoc """
  AfricasTalking SMS integration module.

  Handles SMS sending via AfricasTalking REST API with retry logic and phone number validation.
  """

  require Logger

  @doc """
  Sends an SMS message to a single recipient.

  ## Arguments

    * `to` - Phone number in E.164 format (e.g., "+254712345678")
    * `message` - SMS message content
    * `opts` - Optional keyword list with:
      * `:sender_id` - Custom sender ID (overrides config)
      * `:retry_count` - Current retry attempt (default: 0)

  ## Returns

    * `{:ok, result}` - Success with message ID and delivery info
    * `{:error, reason}` - Failure with error details

  ## Examples

      iex> send_sms("+254712345678", "Your tire service provider is on the way!")
      {:ok, %{message_id: "ATXid_abc123", status: "Success", cost: "KES 0.8000"}}

      iex> send_sms("+1234567890", "Invalid number")
      {:error, "Invalid phone number format"}
  """
  def send_sms(to, message, opts \\ []) do
    with :ok <- validate_phone_number(to),
         {:ok, response} <- send_request(to, message, opts) do
      handle_response(response, to, message, opts)
    else
      {:error, reason} = error ->
        retry_count = Keyword.get(opts, :retry_count, 0)

        Logger.error(
          "SMS send failed: to=#{to}, reason=#{inspect(reason)}, retry_count=#{retry_count}"
        )

        error
    end
  end

  @doc """
  Validates phone number format (E.164).

  E.164 format: +[country code][number]
  Example: +254712345678 (Kenya), +1234567890 (US)
  """
  def validate_phone_number(phone) when is_binary(phone) do
    # E.164 format: starts with +, followed by 1-15 digits
    if Regex.match?(~r/^\+[1-9]\d{1,14}$/, phone) do
      :ok
    else
      {:error, "Invalid phone number format. Expected E.164 format (e.g., +254712345678)"}
    end
  end

  def validate_phone_number(_), do: {:error, "Phone number must be a string"}

  # Private functions

  defp send_request(to, message, opts) do
    config = get_config()
    retry_count = Keyword.get(opts, :retry_count, 0)

    body = %{
      username: config.username,
      to: to,
      message: message,
      from: Keyword.get(opts, :sender_id, config.sender_id)
    }

    headers = [
      {"apiKey", config.api_key},
      {"Content-Type", "application/x-www-form-urlencoded"},
      {"Accept", "application/json"}
    ]

    url = get_api_url(config.environment)

    Logger.info(
      "Sending SMS via AfricasTalking: to=#{to}, environment=#{config.environment}, retry_count=#{retry_count}"
    )

    case Req.post(url,
           form: body,
           headers: headers,
           receive_timeout: 10_000
         ) do
      {:ok, %{status: 201, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_response(response, to, message, opts) do
    retry_count = Keyword.get(opts, :retry_count, 0)

    case response do
      %{"SMSMessageData" => %{"Recipients" => [recipient | _]}} ->
        handle_recipient_response(recipient, to, message, opts, retry_count)

      %{"SMSMessageData" => %{"Message" => error_message}} ->
        Logger.error(
          "AfricasTalking API error: to=#{to}, error=#{error_message}, retry_count=#{retry_count}"
        )

        maybe_retry(to, message, opts, retry_count, error_message)

      _ ->
        Logger.error(
          "Unexpected AfricasTalking response format: to=#{to}, response=#{inspect(response)}, retry_count=#{retry_count}"
        )

        {:error, "Unexpected response format"}
    end
  end

  defp handle_recipient_response(recipient, to, message, opts, retry_count) do
    status_code = recipient["statusCode"]
    status = recipient["status"]
    message_id = recipient["messageId"]
    cost = recipient["cost"]

    case status_code do
      101 ->
        # Success
        Logger.info(
          "SMS sent successfully: to=#{to}, message_id=#{message_id}, status=#{status}, cost=#{cost}, retry_count=#{retry_count}"
        )

        {:ok,
         %{
           message_id: message_id,
           status: status,
           cost: cost,
           phone_number: to
         }}

      102 ->
        # Invalid phone number
        Logger.error(
          "SMS failed: Invalid phone number - to=#{to}, status_code=#{status_code}, status=#{status}"
        )

        {:error, "Invalid phone number"}

      401 ->
        # Risk hold (suspected spam)
        Logger.error(
          "SMS failed: Risk hold - to=#{to}, status_code=#{status_code}, status=#{status}"
        )

        {:error, "Message blocked due to risk hold"}

      402 ->
        # Invalid sender ID
        Logger.error(
          "SMS failed: Invalid sender ID - to=#{to}, status_code=#{status_code}, status=#{status}"
        )

        {:error, "Invalid sender ID"}

      403 ->
        # Invalid credentials
        Logger.error(
          "SMS failed: Invalid credentials - to=#{to}, status_code=#{status_code}, status=#{status}"
        )

        {:error, "Invalid API credentials"}

      404 ->
        # Insufficient balance
        Logger.error(
          "SMS failed: Insufficient balance - to=#{to}, status_code=#{status_code}, status=#{status}"
        )

        {:error, "Insufficient account balance"}

      405 ->
        # Gateway error - retry
        Logger.warning(
          "SMS failed: Gateway error, will retry - to=#{to}, status_code=#{status_code}, status=#{status}, retry_count=#{retry_count}"
        )

        maybe_retry(to, message, opts, retry_count, "Gateway error")

      _ ->
        Logger.error(
          "SMS failed: Unknown status code - to=#{to}, status_code=#{status_code}, status=#{status}"
        )

        {:error, "Unknown error: #{status}"}
    end
  end

  defp maybe_retry(to, message, opts, retry_count, reason) do
    max_retries = 3

    if retry_count < max_retries do
      # Exponential backoff: 1s, 2s, 4s
      backoff_ms = (:math.pow(2, retry_count) * 1000) |> round()

      Logger.info(
        "Retrying SMS after #{backoff_ms}ms: to=#{to}, retry_count=#{retry_count + 1}, max_retries=#{max_retries}"
      )

      Process.sleep(backoff_ms)

      send_sms(to, message, Keyword.put(opts, :retry_count, retry_count + 1))
    else
      Logger.error("SMS failed after #{max_retries} retries: to=#{to}, reason=#{reason}")

      {:error, "Failed after #{max_retries} retries: #{reason}"}
    end
  end

  defp get_config do
    %{
      api_key: get_env!("AFRICAS_TALKING_API_KEY"),
      username: get_env!("AFRICAS_TALKING_USERNAME"),
      sender_id: get_env("AFRICAS_TALKING_SENDER_ID"),
      environment: get_env("AFRICAS_TALKING_ENVIRONMENT", "sandbox")
    }
  end

  defp get_api_url("production"), do: "https://api.africastalking.com/version1/messaging"
  defp get_api_url(_), do: "https://api.sandbox.africastalking.com/version1/messaging"

  defp get_env!(key) do
    System.get_env(key) ||
      raise """
      Environment variable #{key} is missing.
      Please add it to your .env file or system environment.
      """
  end

  defp get_env(key, default \\ nil) do
    System.get_env(key) || default
  end
end
