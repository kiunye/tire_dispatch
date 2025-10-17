defmodule TireDispatchWeb.MPESAWebhookController do
  @moduledoc """
  Handles MPESA callback webhooks for STK Push, B2C, and reversal transactions.
  """

  use TireDispatchWeb, :controller

  require Logger

  alias TireDispatch.Jobs
  alias TireDispatch.Payments

  @doc """
  Handles STK Push callback from Safaricom.

  Callback structure:
  %{
    "Body" => %{
      "stkCallback" => %{
        "MerchantRequestID" => "...",
        "CheckoutRequestID" => "...",
        "ResultCode" => 0,
        "ResultDesc" => "The service request is processed successfully.",
        "CallbackMetadata" => %{
          "Item" => [
            %{"Name" => "Amount", "Value" => 1.0},
            %{"Name" => "MpesaReceiptNumber", "Value" => "..."},
            %{"Name" => "TransactionDate", "Value" => 20231215123456},
            %{"Name" => "PhoneNumber", "Value" => 254712345678}
          ]
        }
      }
    }
  }
  """
  def stk_callback(conn, params) do
    Logger.info("MPESA STK Push callback received", %{params: inspect(params)})

    case extract_stk_callback_data(params) do
      {:ok, callback_data} ->
        process_stk_callback(callback_data)
        json(conn, %{ResultCode: 0, ResultDesc: "Accepted"})

      {:error, reason} ->
        Logger.error("Failed to extract STK callback data", %{
          reason: reason,
          params: inspect(params)
        })

        json(conn, %{ResultCode: 1, ResultDesc: "Rejected"})
    end
  end

  @doc """
  Handles timeout callback from Safaricom when STK Push times out.
  """
  def timeout_callback(conn, params) do
    Logger.warning("MPESA STK Push timeout", %{params: inspect(params)})

    case extract_timeout_data(params) do
      {:ok, %{checkout_request_id: checkout_request_id}} ->
        # Update transaction status to failed
        case Payments.get_transaction_by_mpesa_checkout_request_id(checkout_request_id) do
          nil ->
            Logger.error("Transaction not found for timeout", %{
              checkout_request_id: checkout_request_id
            })

          transaction ->
            Payments.update_transaction(transaction, %{
              status: :failed,
              error_message: "Payment request timed out"
            })

            Logger.info("Transaction marked as failed due to timeout", %{
              transaction_id: transaction.id,
              checkout_request_id: checkout_request_id
            })
        end

      {:error, reason} ->
        Logger.error("Failed to extract timeout data", %{reason: reason})
    end

    json(conn, %{ResultCode: 0, ResultDesc: "Accepted"})
  end

  @doc """
  Handles B2C result callback from Safaricom.

  Callback structure:
  %{
    "Result" => %{
      "ResultType" => 0,
      "ResultCode" => 0,
      "ResultDesc" => "The service request is processed successfully.",
      "OriginatorConversationID" => "...",
      "ConversationID" => "...",
      "TransactionID" => "...",
      "ResultParameters" => %{
        "ResultParameter" => [
          %{"Key" => "TransactionAmount", "Value" => 1000},
          %{"Key" => "TransactionReceipt", "Value" => "..."},
          %{"Key" => "ReceiverPartyPublicName", "Value" => "254712345678 - John Doe"},
          %{"Key" => "TransactionCompletedDateTime", "Value" => "15.12.2023 12:34:56"},
          %{"Key" => "B2CUtilityAccountAvailableFunds", "Value" => 50000.00},
          %{"Key" => "B2CWorkingAccountAvailableFunds", "Value" => 100000.00},
          %{"Key" => "B2CChargesPaidAccountAvailableFunds", "Value" => 0.00}
        ]
      }
    }
  }
  """
  def b2c_result_callback(conn, params) do
    Logger.info("MPESA B2C result callback received", %{params: inspect(params)})

    case extract_b2c_result_data(params) do
      {:ok, result_data} ->
        process_b2c_result(result_data)
        json(conn, %{ResultCode: 0, ResultDesc: "Accepted"})

      {:error, reason} ->
        Logger.error("Failed to extract B2C result data", %{
          reason: reason,
          params: inspect(params)
        })

        json(conn, %{ResultCode: 1, ResultDesc: "Rejected"})
    end
  end

  # Private functions

  defp extract_stk_callback_data(params) do
    with %{"Body" => %{"stkCallback" => callback}} <- params,
         %{"CheckoutRequestID" => checkout_request_id, "ResultCode" => result_code} <- callback do
      callback_data = %{
        checkout_request_id: checkout_request_id,
        merchant_request_id: callback["MerchantRequestID"],
        result_code: result_code,
        result_desc: callback["ResultDesc"]
      }

      # Extract metadata if payment was successful
      callback_data =
        if result_code == 0 && callback["CallbackMetadata"] do
          metadata = extract_callback_metadata(callback["CallbackMetadata"])
          Map.merge(callback_data, metadata)
        else
          callback_data
        end

      {:ok, callback_data}
    else
      _ -> {:error, "Invalid callback structure"}
    end
  end

  defp extract_callback_metadata(%{"Item" => items}) when is_list(items) do
    Enum.reduce(items, %{}, fn item, acc ->
      case item do
        %{"Name" => "Amount", "Value" => value} ->
          Map.put(acc, :amount, value)

        %{"Name" => "MpesaReceiptNumber", "Value" => value} ->
          Map.put(acc, :mpesa_receipt_number, value)

        %{"Name" => "TransactionDate", "Value" => value} ->
          Map.put(acc, :transaction_date, value)

        %{"Name" => "PhoneNumber", "Value" => value} ->
          Map.put(acc, :phone_number, to_string(value))

        _ ->
          acc
      end
    end)
  end

  defp extract_callback_metadata(_), do: %{}

  defp extract_timeout_data(params) do
    case params do
      %{"Body" => %{"stkCallback" => %{"CheckoutRequestID" => checkout_request_id}}} ->
        {:ok, %{checkout_request_id: checkout_request_id}}

      _ ->
        {:error, "Invalid timeout structure"}
    end
  end

  defp process_stk_callback(%{result_code: 0} = callback_data) do
    # Payment successful
    Logger.info("STK Push payment successful", %{callback_data: callback_data})

    transaction =
      Payments.get_transaction_by_mpesa_checkout_request_id(callback_data.checkout_request_id)

    if transaction do
      handle_successful_payment(transaction, callback_data)
    else
      Logger.error("Transaction not found for successful payment", %{
        checkout_request_id: callback_data.checkout_request_id
      })
    end
  end

  defp process_stk_callback(%{result_code: result_code} = callback_data) do
    # Payment failed
    Logger.warning("STK Push payment failed", %{
      result_code: result_code,
      result_desc: callback_data.result_desc,
      checkout_request_id: callback_data.checkout_request_id
    })

    transaction =
      Payments.get_transaction_by_mpesa_checkout_request_id(callback_data.checkout_request_id)

    if transaction do
      handle_failed_payment(transaction, callback_data)
    else
      Logger.error("Transaction not found for failed payment", %{
        checkout_request_id: callback_data.checkout_request_id
      })
    end
  end

  defp handle_successful_payment(transaction, callback_data) do
    # Update transaction with success details
    {:ok, updated_transaction} =
      Payments.update_transaction(transaction, %{
        status: :completed,
        external_transaction_id: callback_data.mpesa_receipt_number,
        mpesa_phone_number: callback_data.phone_number
      })

    Logger.info("Transaction updated with MPESA receipt", %{
      transaction_id: updated_transaction.id,
      mpesa_receipt_number: callback_data.mpesa_receipt_number
    })

    # Update job status to payment_confirmed
    if transaction.job_id do
      confirm_job_payment(transaction.job_id, updated_transaction)
    end
  end

  defp handle_failed_payment(transaction, callback_data) do
    Payments.update_transaction(transaction, %{
      status: :failed,
      error_message: callback_data.result_desc
    })

    Logger.info("Transaction marked as failed", %{
      transaction_id: transaction.id,
      error_message: callback_data.result_desc
    })

    # Optionally cancel the job if payment failed
    if transaction.job_id do
      cancel_job_for_failed_payment(transaction.job_id, callback_data.result_desc)
    end
  end

  defp confirm_job_payment(job_id, updated_transaction) do
    case Jobs.get_job(job_id) do
      {:ok, job} ->
        handle_job_payment_confirmation(job, updated_transaction)

      {:error, :not_found} ->
        Logger.error("Job not found for transaction", %{job_id: job_id})
    end
  end

  defp cancel_job_for_failed_payment(job_id, reason) do
    case Jobs.get_job(job_id) do
      {:ok, job} ->
        Jobs.cancel_job(job, "Payment failed: #{reason}")

        Logger.info("Job cancelled due to payment failure", %{
          job_id: job.id,
          reason: reason
        })

      {:error, :not_found} ->
        Logger.error("Job not found for transaction", %{job_id: job_id})
    end
  end

  defp handle_job_payment_confirmation(job, updated_transaction) do
    case Jobs.confirm_payment(job) do
      {:ok, updated_job} ->
        Logger.info("Job payment confirmed", %{job_id: updated_job.id})
        broadcast_payment_confirmation(updated_job, updated_transaction)

      {:error, reason} ->
        Logger.error("Failed to confirm job payment", %{
          job_id: job.id,
          reason: inspect(reason)
        })
    end
  end

  defp broadcast_payment_confirmation(updated_job, updated_transaction) do
    TireDispatchWeb.Endpoint.broadcast(
      "jobs:#{updated_job.id}",
      "payment_confirmed",
      %{job: updated_job, transaction: updated_transaction}
    )

    TireDispatchWeb.Endpoint.broadcast(
      "driver:#{updated_job.driver_id}:jobs",
      "payment_confirmed",
      %{job: updated_job}
    )
  end

  defp extract_b2c_result_data(params) do
    with %{"Result" => result} <- params,
         %{"ResultCode" => result_code, "ConversationID" => conversation_id} <- result do
      result_data = %{
        result_code: result_code,
        result_desc: result["ResultDesc"],
        conversation_id: conversation_id,
        originator_conversation_id: result["OriginatorConversationID"],
        transaction_id: result["TransactionID"]
      }

      # Extract result parameters if payment was successful
      result_data =
        if result_code == 0 && result["ResultParameters"] do
          params_map = extract_b2c_result_parameters(result["ResultParameters"])
          Map.merge(result_data, params_map)
        else
          result_data
        end

      {:ok, result_data}
    else
      _ -> {:error, "Invalid B2C result structure"}
    end
  end

  defp extract_b2c_result_parameters(%{"ResultParameter" => params}) when is_list(params) do
    Enum.reduce(params, %{}, fn param, acc ->
      case param do
        %{"Key" => "TransactionAmount", "Value" => value} ->
          Map.put(acc, :transaction_amount, value)

        %{"Key" => "TransactionReceipt", "Value" => value} ->
          Map.put(acc, :transaction_receipt, value)

        %{"Key" => "ReceiverPartyPublicName", "Value" => value} ->
          Map.put(acc, :receiver_party_public_name, value)

        %{"Key" => "TransactionCompletedDateTime", "Value" => value} ->
          Map.put(acc, :transaction_completed_datetime, value)

        _ ->
          acc
      end
    end)
  end

  defp extract_b2c_result_parameters(_), do: %{}

  defp process_b2c_result(%{result_code: 0} = result_data) do
    # B2C payment successful
    Logger.info("B2C payment successful", %{result_data: result_data})

    # Find the payout transaction by conversation_id or originator_conversation_id
    # Note: We'll need to store these IDs when initiating the B2C payment
    # For now, we'll log the success and handle the update in the Payments context
    Logger.info("B2C payout completed successfully", %{
      conversation_id: result_data.conversation_id,
      transaction_id: result_data.transaction_id,
      transaction_receipt: result_data[:transaction_receipt]
    })

    # TODO: Update the payout transaction status to completed
    # This will be handled by the Payments context when we integrate B2C with payouts
  end

  defp process_b2c_result(%{result_code: result_code} = result_data) do
    # B2C payment failed
    Logger.warning("B2C payment failed", %{
      result_code: result_code,
      result_desc: result_data.result_desc,
      conversation_id: result_data.conversation_id
    })

    # TODO: Update the payout transaction status to failed
    # This will be handled by the Payments context when we integrate B2C with payouts
  end
end
