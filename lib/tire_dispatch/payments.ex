defmodule TireDispatch.Payments do
  @moduledoc """
  The Payments context handles payment processing, escrow management,
  provider payouts, and refunds for both Stripe and MPESA payment methods.
  """

  import Ecto.Query, warn: false
  alias TireDispatch.Jobs
  alias TireDispatch.Payments.Transaction
  alias TireDispatch.Repo
  require Logger

  @doc """
  Creates a payment transaction record.

  ## Arguments

    * `job_id` - UUID of the job being paid for
    * `amount_cents` - Payment amount in cents
    * `driver_id` - UUID of the driver making the payment
    * `payment_method` - Payment method (:stripe or :mpesa)

  ## Returns

    * `{:ok, transaction}` on success
    * `{:error, changeset}` if validation fails
  """
  def create_payment(job_id, amount_cents, driver_id, payment_method \\ :stripe) do
    attrs = %{
      job_id: job_id,
      amount_cents: amount_cents,
      driver_id: driver_id,
      type: :payment,
      status: :pending,
      payment_method: payment_method,
      currency: "usd"
    }

    %Transaction{}
    |> Transaction.changeset(attrs)
    |> Repo.insert()
    |> tap(&log_transaction_created/1)
  end

  @doc """
  Gets a single transaction by ID.

  Raises `Ecto.NoResultsError` if the Transaction does not exist.

  ## Arguments

    * `id` - UUID of the transaction

  ## Returns

    * Transaction struct
  """
  def get_transaction!(id) do
    Repo.get!(Transaction, id)
  end

  @doc """
  Gets a transaction by ID with preloaded associations.

  ## Arguments

    * `id` - UUID of the transaction

  ## Returns

    * `{:ok, transaction}` if found
    * `{:error, :not_found}` if not found
  """
  def get_transaction(id) do
    case Repo.get(Transaction, id) do
      nil -> {:error, :not_found}
      transaction -> {:ok, Repo.preload(transaction, [:job, :driver, :provider])}
    end
  end

  @doc """
  Lists all pending payout transactions.

  ## Returns

    * List of Transaction structs with type :payout and status :pending
  """
  def list_pending_payouts do
    from(t in Transaction,
      where: t.type == :payout and t.status == :pending,
      preload: [:job, :provider]
    )
    |> Repo.all()
  end

  @doc """
  Updates a transaction's status.

  ## Arguments

    * `transaction` - Transaction struct to update
    * `attrs` - Map with status and optional external_transaction_id and error_message

  ## Returns

    * `{:ok, transaction}` on success
    * `{:error, changeset}` if validation fails
  """
  def update_transaction_status(transaction, attrs) do
    transaction
    |> Transaction.status_changeset(attrs)
    |> Repo.update()
    |> tap(&log_transaction_updated/1)
  end

  @doc """
  Marks a payment as completed after successful payment processing.

  ## Arguments

    * `transaction` - Transaction struct to update
    * `external_transaction_id` - Stripe charge ID or MPESA receipt number

  ## Returns

    * `{:ok, transaction}` on success
    * `{:error, changeset}` if validation fails
  """
  def mark_payment_completed(transaction, external_transaction_id) do
    update_transaction_status(transaction, %{
      status: :completed,
      external_transaction_id: external_transaction_id
    })
  end

  @doc """
  Marks a payment as failed with an error message.

  ## Arguments

    * `transaction` - Transaction struct to update
    * `error_message` - Description of the failure

  ## Returns

    * `{:ok, transaction}` on success
    * `{:error, changeset}` if validation fails
  """
  def mark_payment_failed(transaction, error_message) do
    update_transaction_status(transaction, %{
      status: :failed,
      error_message: error_message
    })
  end

  @doc """
  Processes a provider payout for a completed job.

  Calculates the payout amount by subtracting the platform commission
  and creates a payout transaction record.

  ## Arguments

    * `job_id` - UUID of the completed job

  ## Returns

    * `{:ok, payout_transaction}` on success
    * `{:error, reason}` if job not found or payout already processed
  """
  def process_provider_payout(job_id) do
    with {:ok, job} <- Jobs.get_job(job_id),
         :ok <- validate_job_for_payout(job),
         {:ok, payment_transaction} <- get_job_payment_transaction(job_id),
         payout_amount <- calculate_payout_amount(payment_transaction.amount_cents) do
      create_payout_transaction(job, payment_transaction, payout_amount)
    end
  end

  @doc """
  Processes a refund for a payment transaction.

  This function handles refunds for both Stripe and MPESA payments.
  For Stripe, it calls the Stripe Refunds API. For MPESA, it initiates
  a reversal via the MPESA API.

  ## Arguments

    * `transaction` - Original payment transaction to refund
    * `reason` - Reason for the refund

  ## Returns

    * `{:ok, refund_transaction}` on success
    * `{:error, reason}` if refund fails
  """
  def refund_payment(transaction, reason) do
    with :ok <- validate_refundable_transaction(transaction),
         {:ok, refund_result} <- process_refund_by_method(transaction),
         {:ok, refund_transaction} <-
           create_refund_transaction(transaction, reason, refund_result) do
      Logger.info("Refund processed successfully",
        original_transaction_id: transaction.id,
        refund_transaction_id: refund_transaction.id,
        payment_method: transaction.payment_method
      )

      {:ok, refund_transaction}
    else
      {:error, reason} = error ->
        Logger.error("Refund processing failed",
          transaction_id: transaction.id,
          payment_method: transaction.payment_method,
          reason: inspect(reason)
        )

        error
    end
  end

  @doc """
  Executes a Stripe Connect transfer to send payout to provider.

  This function transfers funds from the platform Stripe account to the
  provider's connected Stripe account.

  ## Arguments

    * `payout_transaction` - Transaction struct with type :payout and status :pending

  ## Returns

    * `{:ok, transaction}` on success with updated status and stripe_transaction_id
    * `{:error, reason}` if transfer fails
  """
  def execute_stripe_transfer(payout_transaction) do
    with {:ok, provider} <- get_provider_for_payout(payout_transaction),
         :ok <- validate_stripe_account(provider),
         {:ok, transfer} <- create_stripe_transfer(payout_transaction, provider) do
      update_transaction_status(payout_transaction, %{
        status: :completed,
        external_transaction_id: transfer.id
      })
    else
      {:error, %Stripe.Error{} = error} ->
        Logger.error("Stripe transfer failed",
          payout_id: payout_transaction.id,
          provider_id: payout_transaction.provider_id,
          error: error.message
        )

        mark_payment_failed(payout_transaction, error.message)

      {:error, reason} ->
        Logger.error("Payout transfer failed",
          payout_id: payout_transaction.id,
          reason: inspect(reason)
        )

        mark_payment_failed(payout_transaction, inspect(reason))
    end
  end

  @doc """
  Lists all transactions for a specific job.

  ## Arguments

    * `job_id` - UUID of the job

  ## Returns

    * List of Transaction structs
  """
  def list_job_transactions(job_id) do
    from(t in Transaction,
      where: t.job_id == ^job_id,
      order_by: [desc: t.inserted_at],
      preload: [:driver, :provider]
    )
    |> Repo.all()
  end

  @doc """
  Gets the payment transaction for a job.

  ## Arguments

    * `job_id` - UUID of the job

  ## Returns

    * `{:ok, transaction}` if found
    * `{:error, :not_found}` if not found
  """
  def get_job_payment_transaction(job_id) do
    case Repo.get_by(Transaction, job_id: job_id, type: :payment, status: :completed) do
      nil -> {:error, :payment_not_found}
      transaction -> {:ok, transaction}
    end
  end

  @doc """
  Gets a transaction by MPESA CheckoutRequestID.

  ## Arguments

    * `checkout_request_id` - MPESA CheckoutRequestID from STK Push

  ## Returns

    * Transaction struct or nil if not found
  """
  def get_transaction_by_mpesa_checkout_request_id(checkout_request_id) do
    Repo.get_by(Transaction, mpesa_checkout_request_id: checkout_request_id)
  end

  @doc """
  Updates a transaction with arbitrary attributes.

  ## Arguments

    * `transaction` - Transaction struct to update
    * `attrs` - Map of attributes to update

  ## Returns

    * `{:ok, transaction}` on success
    * `{:error, changeset}` if validation fails
  """
  def update_transaction(transaction, attrs) do
    transaction
    |> Transaction.changeset(attrs)
    |> Repo.update()
    |> tap(&log_transaction_updated/1)
  end

  @doc """
  Initiates a Stripe Checkout session for driver payment.

  Creates a Stripe Checkout session with the job details and returns
  the checkout URL for redirect.

  ## Arguments

    * `job_id` - UUID of the job being paid for
    * `amount_cents` - Payment amount in cents

  ## Returns

    * `{:ok, %{checkout_url: url, session_id: id}}` on success
    * `{:error, reason}` if Stripe API call fails
  """
  def initiate_stripe_checkout(job_id, amount_cents) do
    with {:ok, job} <- Jobs.get_job(job_id),
         {:ok, session} <- create_stripe_session(job, amount_cents) do
      Logger.info("Stripe Checkout session created",
        job_id: job_id,
        session_id: session.id,
        amount_cents: amount_cents
      )

      {:ok, %{checkout_url: session.url, session_id: session.id}}
    else
      {:error, %Stripe.Error{} = error} ->
        Logger.error("Stripe Checkout session creation failed",
          job_id: job_id,
          error: error.message
        )

        {:error, error.message}

      {:error, reason} ->
        Logger.error("Failed to initiate Stripe Checkout",
          job_id: job_id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  # Private helper functions

  defp validate_job_for_payout(job) do
    cond do
      job.status != :completed ->
        {:error, :job_not_completed}

      is_nil(job.provider_id) ->
        {:error, :no_provider_assigned}

      payout_exists?(job.id) ->
        {:error, :payout_already_processed}

      true ->
        :ok
    end
  end

  defp payout_exists?(job_id) do
    Repo.exists?(
      from t in Transaction,
        where: t.job_id == ^job_id and t.type == :payout
    )
  end

  defp calculate_payout_amount(job_amount_cents) do
    commission_percent = Application.get_env(:tire_dispatch, :platform_commission_percent, 15)
    commission_amount = div(job_amount_cents * commission_percent, 100)
    job_amount_cents - commission_amount
  end

  defp create_payout_transaction(job, payment_transaction, payout_amount) do
    attrs = %{
      job_id: job.id,
      provider_id: job.provider_id,
      amount_cents: payout_amount,
      type: :payout,
      status: :pending,
      payment_method: payment_transaction.payment_method,
      currency: payment_transaction.currency,
      notes: "Payout for job #{job.id}"
    }

    %Transaction{}
    |> Transaction.changeset(attrs)
    |> Repo.insert()
    |> tap(&log_payout_created/1)
  end

  defp log_transaction_created({:ok, transaction}) do
    Logger.info("Transaction created",
      transaction_id: transaction.id,
      type: transaction.type,
      amount_cents: transaction.amount_cents,
      payment_method: transaction.payment_method
    )

    {:ok, transaction}
  end

  defp log_transaction_created(error), do: error

  defp log_transaction_updated({:ok, transaction}) do
    Logger.info("Transaction updated",
      transaction_id: transaction.id,
      status: transaction.status,
      external_transaction_id: transaction.external_transaction_id
    )

    {:ok, transaction}
  end

  defp log_transaction_updated(error), do: error

  defp log_payout_created({:ok, payout}) do
    Logger.info("Payout transaction created",
      payout_id: payout.id,
      job_id: payout.job_id,
      provider_id: payout.provider_id,
      amount_cents: payout.amount_cents
    )

    {:ok, payout}
  end

  defp log_payout_created(error), do: error

  defp create_stripe_session(job, amount_cents) do
    success_url = get_success_url(job.id)
    cancel_url = get_cancel_url(job.id)

    params = %{
      mode: "payment",
      line_items: [
        %{
          price_data: %{
            currency: "usd",
            product_data: %{
              name: format_service_name(job.service_type),
              description: "Tire service for #{job.vehicle_type} - #{job.urgency_tier} priority"
            },
            unit_amount: amount_cents
          },
          quantity: 1
        }
      ],
      success_url: success_url,
      cancel_url: cancel_url,
      client_reference_id: job.id,
      metadata: %{
        job_id: job.id,
        driver_id: job.driver_id,
        service_type: job.service_type
      }
    }

    Stripe.Checkout.Session.create(params)
  end

  defp format_service_name(service_type) do
    case service_type do
      :flat_repair -> "Flat Tire Repair"
      :nail_removal -> "Nail Removal"
      :air_fill -> "Tire Air Fill"
      :new_tire -> "New Tire Installation"
      :replacement -> "Tire Replacement"
      _ -> "Tire Service"
    end
  end

  defp get_success_url(job_id) do
    base_url = get_base_url()
    "#{base_url}/driver/jobs/#{job_id}/payment-success"
  end

  defp get_cancel_url(job_id) do
    base_url = get_base_url()
    "#{base_url}/driver/jobs/#{job_id}/payment-cancelled"
  end

  defp get_base_url do
    endpoint_config = Application.get_env(:tire_dispatch, TireDispatchWeb.Endpoint)
    url_config = Keyword.get(endpoint_config, :url, [])
    host = Keyword.get(url_config, :host, "localhost")
    port = Keyword.get(url_config, :port, 4000)
    scheme = Keyword.get(url_config, :scheme, "http")

    if port in [80, 443] do
      "#{scheme}://#{host}"
    else
      "#{scheme}://#{host}:#{port}"
    end
  end

  defp get_provider_for_payout(payout_transaction) do
    case Repo.get(TireDispatch.Providers.Provider, payout_transaction.provider_id) do
      nil -> {:error, :provider_not_found}
      provider -> {:ok, provider}
    end
  end

  defp validate_stripe_account(provider) do
    cond do
      provider.payout_method != :stripe ->
        {:error, :invalid_payout_method}

      is_nil(provider.stripe_account_id) or provider.stripe_account_id == "" ->
        {:error, :stripe_account_not_configured}

      true ->
        :ok
    end
  end

  defp create_stripe_transfer(payout_transaction, provider) do
    params = %{
      amount: payout_transaction.amount_cents,
      currency: payout_transaction.currency,
      destination: provider.stripe_account_id,
      description: "Payout for job #{payout_transaction.job_id}",
      metadata: %{
        job_id: payout_transaction.job_id,
        provider_id: provider.id,
        payout_transaction_id: payout_transaction.id
      }
    }

    Logger.info("Creating Stripe transfer",
      payout_id: payout_transaction.id,
      amount_cents: payout_transaction.amount_cents,
      destination: provider.stripe_account_id
    )

    Stripe.Transfer.create(params)
  end

  defp validate_refundable_transaction(transaction) do
    cond do
      transaction.type != :payment ->
        {:error, :not_a_payment_transaction}

      transaction.status != :completed ->
        {:error, :payment_not_completed}

      refund_already_exists?(transaction.id) ->
        {:error, :refund_already_processed}

      is_nil(transaction.external_transaction_id) ->
        {:error, :no_external_transaction_id}

      true ->
        :ok
    end
  end

  defp refund_already_exists?(transaction_id) do
    Repo.exists?(
      from t in Transaction,
        where: t.reference_transaction_id == ^transaction_id and t.type == :refund
    )
  end

  defp process_refund_by_method(transaction) do
    case transaction.payment_method do
      :stripe ->
        process_stripe_refund(transaction)

      :mpesa ->
        process_mpesa_refund(transaction)

      _ ->
        {:error, :unsupported_payment_method}
    end
  end

  defp process_stripe_refund(transaction) do
    params = %{
      charge: transaction.external_transaction_id,
      metadata: %{
        original_transaction_id: transaction.id,
        job_id: transaction.job_id
      }
    }

    case Stripe.Refund.create(params) do
      {:ok, refund} ->
        Logger.info("Stripe refund created",
          refund_id: refund.id,
          original_transaction_id: transaction.id,
          amount: refund.amount
        )

        {:ok, %{external_id: refund.id, amount: refund.amount}}

      {:error, %Stripe.Error{} = error} ->
        Logger.error("Stripe refund failed",
          transaction_id: transaction.id,
          charge_id: transaction.external_transaction_id,
          error: error.message
        )

        {:error, error.message}
    end
  end

  defp process_mpesa_refund(transaction) do
    # Convert amount from cents to KES (assuming 1 KES = 100 cents)
    amount_kes = div(transaction.amount_cents, 100)

    case TireDispatch.Payments.MPESA.initiate_reversal(
           transaction.external_transaction_id,
           amount_kes,
           "Refund for job #{transaction.job_id}"
         ) do
      {:ok, reversal_result} ->
        Logger.info("MPESA reversal initiated",
          transaction_id: transaction.id,
          conversation_id: reversal_result.conversation_id
        )

        # Return the conversation_id as the external_id for tracking
        {:ok,
         %{
           external_id: reversal_result.conversation_id,
           amount: transaction.amount_cents
         }}

      {:error, reason} ->
        Logger.error("MPESA reversal failed",
          transaction_id: transaction.id,
          mpesa_transaction_id: transaction.external_transaction_id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp create_refund_transaction(original_transaction, reason, refund_result) do
    attrs = %{
      job_id: original_transaction.job_id,
      driver_id: original_transaction.driver_id,
      amount_cents: refund_result.amount,
      type: :refund,
      status: :completed,
      payment_method: original_transaction.payment_method,
      currency: original_transaction.currency,
      external_transaction_id: refund_result.external_id,
      reference_transaction_id: original_transaction.id,
      notes: reason
    }

    %Transaction{}
    |> Transaction.changeset(attrs)
    |> Repo.insert()
    |> tap(&log_refund_created/1)
  end

  defp log_refund_created({:ok, refund}) do
    Logger.info("Refund transaction created",
      refund_id: refund.id,
      original_transaction_id: refund.reference_transaction_id,
      amount_cents: refund.amount_cents
    )

    {:ok, refund}
  end

  defp log_refund_created(error), do: error
end
