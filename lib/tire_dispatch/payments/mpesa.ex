defmodule TireDispatch.Payments.MPESA do
  @moduledoc """
  MPESA integration module for handling mobile money payments and payouts.

  Provides functionality for:
  - OAuth token generation and caching
  - STK Push (Lipa Na MPESA Online) for C2B payments
  - B2C payments for provider payouts
  - Transaction status queries
  - Reversals for refunds
  """

  require Logger

  @token_cache_table :mpesa_token_cache

  # Configuration helpers
  defp config(key), do: Application.get_env(:tire_dispatch, __MODULE__)[key]

  defp consumer_key, do: config(:consumer_key)
  defp consumer_secret, do: config(:consumer_secret)
  defp shortcode, do: config(:shortcode)
  defp passkey, do: config(:passkey)
  defp initiator_name, do: config(:initiator_name)
  defp security_credential, do: config(:security_credential)
  defp environment, do: config(:environment) || "sandbox"
  defp callback_url, do: config(:callback_url)
  defp timeout_url, do: config(:timeout_url)
  defp result_url, do: config(:result_url)

  # API Base URLs
  defp base_url do
    case environment() do
      "production" -> "https://api.safaricom.co.ke"
      _ -> "https://sandbox.safaricom.co.ke"
    end
  end

  @doc """
  Initializes the ETS table for token caching.
  Should be called during application startup.
  """
  def init_cache do
    case :ets.whereis(@token_cache_table) do
      :undefined ->
        :ets.new(@token_cache_table, [:set, :public, :named_table])
        Logger.info("MPESA token cache initialized")
        :ok

      _table ->
        Logger.debug("MPESA token cache already exists")
        :ok
    end
  end

  @doc """
  Generates an OAuth access token from Safaricom API.
  Caches the token in ETS for reuse until expiration.

  ## Returns

    * `{:ok, token}` - Successfully generated or retrieved cached token
    * `{:error, reason}` - Failed to generate token
  """
  def generate_access_token do
    # Check cache first
    case get_cached_token() do
      {:ok, token} ->
        {:ok, token}

      :expired ->
        fetch_new_token()
    end
  end

  defp get_cached_token do
    case :ets.lookup(@token_cache_table, :access_token) do
      [{:access_token, token, expires_at}] ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
          {:ok, token}
        else
          :expired
        end

      [] ->
        :expired
    end
  end

  defp fetch_new_token do
    url = "#{base_url()}/oauth/v1/generate?grant_type=client_credentials"
    auth = Base.encode64("#{consumer_key()}:#{consumer_secret()}")

    headers = [
      {"Authorization", "Basic #{auth}"},
      {"Content-Type", "application/json"}
    ]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        token = body["access_token"]
        expires_in = body["expires_in"] || 3600

        # Cache token with expiration (subtract 60 seconds for safety margin)
        expires_at = DateTime.add(DateTime.utc_now(), expires_in - 60, :second)
        :ets.insert(@token_cache_table, {:access_token, token, expires_at})

        Logger.info("MPESA access token generated successfully")
        {:ok, token}

      {:ok, %{status: status, body: body}} ->
        Logger.error("MPESA OAuth failed", %{status: status, body: inspect(body)})
        {:error, "OAuth failed with status #{status}"}

      {:error, reason} ->
        Logger.error("MPESA OAuth request failed", %{reason: inspect(reason)})
        {:error, reason}
    end
  end

  @doc """
  Clears the cached access token.
  Useful for testing or forcing token refresh.
  """
  def clear_token_cache do
    :ets.delete(@token_cache_table, :access_token)
    :ok
  end

  @doc """
  Initiates an STK Push (Lipa Na MPESA Online) request for driver payments.

  ## Arguments

    * `phone_number` - The driver's phone number in format 254XXXXXXXXX
    * `amount` - The amount in KES (Kenyan Shillings)
    * `account_reference` - Reference for the transaction (e.g., job_id)
    * `transaction_desc` - Description of the transaction

  ## Returns

    * `{:ok, %{checkout_request_id: id, merchant_request_id: id}}` - Successfully initiated
    * `{:error, reason}` - Failed to initiate STK Push
  """
  def initiate_stk_push(phone_number, amount, account_reference, transaction_desc) do
    with {:ok, token} <- generate_access_token(),
         {:ok, password} <- generate_stk_password(),
         {:ok, response} <-
           send_stk_push_request(
             token,
             phone_number,
             amount,
             account_reference,
             transaction_desc,
             password
           ) do
      {:ok, response}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp generate_stk_password do
    timestamp = get_timestamp()
    password_string = "#{shortcode()}#{passkey()}#{timestamp}"
    password = Base.encode64(password_string)
    {:ok, %{password: password, timestamp: timestamp}}
  end

  defp get_timestamp do
    DateTime.utc_now()
    |> Calendar.strftime("%Y%m%d%H%M%S")
  end

  defp send_stk_push_request(token, phone_number, amount, account_reference, transaction_desc, %{
         password: password,
         timestamp: timestamp
       }) do
    url = "#{base_url()}/mpesa/stkpush/v1/processrequest"

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"}
    ]

    body = %{
      "BusinessShortCode" => shortcode(),
      "Password" => password,
      "Timestamp" => timestamp,
      "TransactionType" => "CustomerPayBillOnline",
      "Amount" => amount,
      "PartyA" => phone_number,
      "PartyB" => shortcode(),
      "PhoneNumber" => phone_number,
      "CallBackURL" => callback_url(),
      "AccountReference" => account_reference,
      "TransactionDesc" => transaction_desc
    }

    case Req.post(url, json: body, headers: headers) do
      {:ok, %{status: 200, body: response_body}} ->
        case response_body do
          %{
            "ResponseCode" => "0",
            "CheckoutRequestID" => checkout_request_id,
            "MerchantRequestID" => merchant_request_id
          } ->
            Logger.info("STK Push initiated successfully", %{
              checkout_request_id: checkout_request_id,
              merchant_request_id: merchant_request_id,
              phone_number: phone_number,
              amount: amount
            })

            {:ok,
             %{
               checkout_request_id: checkout_request_id,
               merchant_request_id: merchant_request_id
             }}

          %{"ResponseCode" => code, "ResponseDescription" => description} ->
            Logger.error("STK Push failed", %{
              response_code: code,
              description: description,
              phone_number: phone_number
            })

            {:error, "STK Push failed: #{description}"}

          _ ->
            Logger.error("Unexpected STK Push response", %{body: inspect(response_body)})
            {:error, "Unexpected response from MPESA"}
        end

      {:ok, %{status: status, body: body}} ->
        Logger.error("STK Push request failed", %{status: status, body: inspect(body)})
        {:error, "STK Push request failed with status #{status}"}

      {:error, reason} ->
        Logger.error("STK Push request error", %{reason: inspect(reason)})
        {:error, reason}
    end
  end

  @doc """
  Queries the status of an STK Push transaction.

  This is useful for checking the status of a transaction that may have timed out
  or when the callback hasn't been received.

  ## Arguments

    * `checkout_request_id` - The CheckoutRequestID from the STK Push initiation

  ## Returns

    * `{:ok, %{result_code: code, result_desc: desc, ...}}` - Transaction status
    * `{:error, reason}` - Failed to query status
  """
  def query_transaction_status(checkout_request_id) do
    with {:ok, token} <- generate_access_token(),
         {:ok, password_data} <- generate_stk_password(),
         {:ok, response} <- send_status_query_request(token, checkout_request_id, password_data) do
      {:ok, response}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp send_status_query_request(token, checkout_request_id, %{
         password: password,
         timestamp: timestamp
       }) do
    url = "#{base_url()}/mpesa/stkpushquery/v1/query"

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"}
    ]

    body = %{
      "BusinessShortCode" => shortcode(),
      "Password" => password,
      "Timestamp" => timestamp,
      "CheckoutRequestID" => checkout_request_id
    }

    case Req.post(url, json: body, headers: headers) do
      {:ok, %{status: 200, body: response_body}} ->
        case response_body do
          %{"ResponseCode" => "0", "ResultCode" => result_code} ->
            Logger.info("Transaction status query successful", %{
              checkout_request_id: checkout_request_id,
              result_code: result_code,
              result_desc: response_body["ResultDesc"]
            })

            {:ok,
             %{
               result_code: result_code,
               result_desc: response_body["ResultDesc"],
               merchant_request_id: response_body["MerchantRequestID"],
               checkout_request_id: checkout_request_id
             }}

          %{"ResponseCode" => code, "ResponseDescription" => description} ->
            Logger.error("Transaction status query failed", %{
              response_code: code,
              description: description,
              checkout_request_id: checkout_request_id
            })

            {:error, "Status query failed: #{description}"}

          _ ->
            Logger.error("Unexpected status query response", %{body: inspect(response_body)})
            {:error, "Unexpected response from MPESA"}
        end

      {:ok, %{status: status, body: body}} ->
        Logger.error("Status query request failed", %{status: status, body: inspect(body)})
        {:error, "Status query request failed with status #{status}"}

      {:error, reason} ->
        Logger.error("Status query request error", %{reason: inspect(reason)})
        {:error, reason}
    end
  end

  @doc """
  Initiates a B2C (Business to Customer) payment for provider payouts.

  This sends money from the business account to a provider's mobile money wallet.

  ## Arguments

    * `phone_number` - Provider's phone number in format 254XXXXXXXXX
    * `amount` - Amount to send in KES (Kenyan Shillings)
    * `remarks` - Description/remarks for the transaction

  ## Returns

    * `{:ok, %{conversation_id: id, originator_conversation_id: id}}` - Successfully initiated
    * `{:error, reason}` - Failed to initiate B2C payment
  """
  def initiate_b2c_payment(phone_number, amount, remarks) do
    with {:ok, token} <- generate_access_token(),
         {:ok, response} <- send_b2c_request(token, phone_number, amount, remarks) do
      {:ok, response}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp send_b2c_request(token, phone_number, amount, remarks) do
    url = "#{base_url()}/mpesa/b2c/v1/paymentrequest"

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"}
    ]

    body = %{
      "InitiatorName" => initiator_name(),
      "SecurityCredential" => security_credential(),
      "CommandID" => "BusinessPayment",
      "Amount" => amount,
      "PartyA" => shortcode(),
      "PartyB" => phone_number,
      "Remarks" => remarks,
      "QueueTimeOutURL" => timeout_url(),
      "ResultURL" => result_url(),
      "Occasion" => "Provider Payout"
    }

    case Req.post(url, json: body, headers: headers) do
      {:ok, %{status: 200, body: response_body}} ->
        case response_body do
          %{
            "ResponseCode" => "0",
            "ConversationID" => conversation_id,
            "OriginatorConversationID" => originator_conversation_id
          } ->
            Logger.info("B2C payment initiated successfully", %{
              conversation_id: conversation_id,
              originator_conversation_id: originator_conversation_id,
              phone_number: phone_number,
              amount: amount
            })

            {:ok,
             %{
               conversation_id: conversation_id,
               originator_conversation_id: originator_conversation_id
             }}

          %{"ResponseCode" => code, "ResponseDescription" => description} ->
            Logger.error("B2C payment failed", %{
              response_code: code,
              description: description,
              phone_number: phone_number
            })

            {:error, "B2C payment failed: #{description}"}

          _ ->
            Logger.error("Unexpected B2C response", %{body: inspect(response_body)})
            {:error, "Unexpected response from MPESA"}
        end

      {:ok, %{status: status, body: body}} ->
        Logger.error("B2C request failed", %{status: status, body: inspect(body)})
        {:error, "B2C request failed with status #{status}"}

      {:error, reason} ->
        Logger.error("B2C request error", %{reason: inspect(reason)})
        {:error, reason}
    end
  end

  @doc """
  Initiates a reversal (refund) of an MPESA transaction.

  This reverses a completed MPESA transaction and returns the funds to the customer.

  ## Arguments

    * `transaction_id` - The MPESA TransactionID to reverse
    * `amount` - Amount to reverse in KES (Kenyan Shillings)
    * `remarks` - Description/remarks for the reversal

  ## Returns

    * `{:ok, %{conversation_id: id, originator_conversation_id: id}}` - Successfully initiated
    * `{:error, reason}` - Failed to initiate reversal
  """
  def initiate_reversal(transaction_id, amount, remarks) do
    with {:ok, token} <- generate_access_token(),
         {:ok, response} <- send_reversal_request(token, transaction_id, amount, remarks) do
      {:ok, response}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp send_reversal_request(token, transaction_id, amount, remarks) do
    url = "#{base_url()}/mpesa/reversal/v1/request"

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"}
    ]

    body = %{
      "Initiator" => initiator_name(),
      "SecurityCredential" => security_credential(),
      "CommandID" => "TransactionReversal",
      "TransactionID" => transaction_id,
      "Amount" => amount,
      "ReceiverParty" => shortcode(),
      "RecieverIdentifierType" => "11",
      "Remarks" => remarks,
      "QueueTimeOutURL" => timeout_url(),
      "ResultURL" => result_url(),
      "Occasion" => "Refund"
    }

    case Req.post(url, json: body, headers: headers) do
      {:ok, %{status: 200, body: response_body}} ->
        case response_body do
          %{
            "ResponseCode" => "0",
            "ConversationID" => conversation_id,
            "OriginatorConversationID" => originator_conversation_id
          } ->
            Logger.info("Reversal initiated successfully", %{
              conversation_id: conversation_id,
              originator_conversation_id: originator_conversation_id,
              transaction_id: transaction_id,
              amount: amount
            })

            {:ok,
             %{
               conversation_id: conversation_id,
               originator_conversation_id: originator_conversation_id
             }}

          %{"ResponseCode" => code, "ResponseDescription" => description} ->
            Logger.error("Reversal failed", %{
              response_code: code,
              description: description,
              transaction_id: transaction_id
            })

            {:error, "Reversal failed: #{description}"}

          _ ->
            Logger.error("Unexpected reversal response", %{body: inspect(response_body)})
            {:error, "Unexpected response from MPESA"}
        end

      {:ok, %{status: status, body: body}} ->
        Logger.error("Reversal request failed", %{status: status, body: inspect(body)})
        {:error, "Reversal request failed with status #{status}"}

      {:error, reason} ->
        Logger.error("Reversal request error", %{reason: inspect(reason)})
        {:error, reason}
    end
  end
end
