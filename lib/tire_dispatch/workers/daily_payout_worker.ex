defmodule TireDispatch.Workers.DailyPayoutWorker do
  @moduledoc """
  Oban worker that processes daily provider payouts.

  Runs daily at 2 AM via Oban cron to:
  - Query all jobs completed in the previous 24 hours
  - Calculate provider payouts (job amount - platform commission)
  - Transfer funds via Stripe Connect or MPESA B2C based on provider payout method
  - Update transaction records with transfer results

  Requirements: 7.5, 7.7, 7.8, 7.9, 11.2
  """

  use Oban.Worker, queue: :payments

  import Ecto.Query, warn: false
  alias TireDispatch.Jobs.Job
  alias TireDispatch.Payments
  alias TireDispatch.Repo
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Starting daily payout processing")

    yesterday = Date.add(Date.utc_today(), -1)
    start_time = DateTime.new!(yesterday, ~T[00:00:00], "Etc/UTC")
    end_time = DateTime.new!(yesterday, ~T[23:59:59], "Etc/UTC")

    # Query jobs completed in the previous 24 hours
    jobs =
      from(j in Job,
        where: j.status == :completed,
        where: j.completed_at >= ^start_time and j.completed_at <= ^end_time,
        where: not is_nil(j.provider_id),
        preload: [:provider]
      )
      |> Repo.all()

    Logger.info("Found #{length(jobs)} completed jobs for payout processing")

    # Process each job
    results =
      Enum.map(jobs, fn job ->
        process_job_payout(job)
      end)

    # Count successes and failures
    successes = Enum.count(results, &match?({:ok, _}, &1))
    failures = Enum.count(results, &match?({:error, _}, &1))

    Logger.info("Daily payout processing complete",
      total_jobs: length(jobs),
      successful_payouts: successes,
      failed_payouts: failures
    )

    :ok
  end

  defp process_job_payout(job) do
    Logger.info("Processing payout for job", job_id: job.id, provider_id: job.provider_id)

    with {:ok, payout_transaction} <- Payments.process_provider_payout(job.id),
         {:ok, completed_transaction} <- transfer_payout(payout_transaction, job.provider) do
      Logger.info("Payout processed successfully",
        job_id: job.id,
        payout_id: completed_transaction.id,
        amount_cents: completed_transaction.amount_cents,
        payment_method: completed_transaction.payment_method
      )

      {:ok, completed_transaction}
    else
      {:error, :payout_already_processed} ->
        Logger.debug("Payout already processed for job", job_id: job.id)
        {:ok, :already_processed}

      {:error, reason} = error ->
        Logger.error("Failed to process payout",
          job_id: job.id,
          provider_id: job.provider_id,
          reason: inspect(reason)
        )

        error
    end
  end

  defp transfer_payout(payout_transaction, provider) do
    case provider.payout_method do
      :stripe ->
        transfer_via_stripe(payout_transaction)

      :mpesa ->
        transfer_via_mpesa(payout_transaction, provider)

      _ ->
        Logger.error("Unsupported payout method",
          payout_id: payout_transaction.id,
          payout_method: provider.payout_method
        )

        {:error, :unsupported_payout_method}
    end
  end

  defp transfer_via_stripe(payout_transaction) do
    Logger.info("Initiating Stripe Connect transfer",
      payout_id: payout_transaction.id,
      amount_cents: payout_transaction.amount_cents
    )

    Payments.execute_stripe_transfer(payout_transaction)
  end

  defp transfer_via_mpesa(payout_transaction, provider) do
    Logger.info("Initiating MPESA B2C payment",
      payout_id: payout_transaction.id,
      amount_cents: payout_transaction.amount_cents,
      phone_number: provider.mpesa_phone_number
    )

    # Convert amount from cents to KES (assuming 1 KES = 100 cents)
    amount_kes = div(payout_transaction.amount_cents, 100)

    case TireDispatch.Payments.MPESA.initiate_b2c_payment(
           provider.mpesa_phone_number,
           amount_kes,
           "Payout for job #{payout_transaction.job_id}"
         ) do
      {:ok, b2c_result} ->
        Logger.info("MPESA B2C payment initiated",
          payout_id: payout_transaction.id,
          conversation_id: b2c_result.conversation_id
        )

        # Update transaction with conversation_id and mark as completed
        # Note: In production, you'd wait for the B2C callback to confirm completion
        # For now, we mark as completed immediately
        Payments.update_transaction_status(payout_transaction, %{
          status: :completed,
          external_transaction_id: b2c_result.conversation_id
        })

      {:error, reason} ->
        Logger.error("MPESA B2C payment failed",
          payout_id: payout_transaction.id,
          reason: inspect(reason)
        )

        Payments.mark_payment_failed(payout_transaction, inspect(reason))
    end
  end
end
