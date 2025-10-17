defmodule TireDispatchWeb.WebhookController do
  @moduledoc """
  Controller for handling Stripe webhook events.

  This controller processes webhook events from Stripe, particularly
  the checkout.session.completed event for payment confirmations.
  """
  use TireDispatchWeb, :controller

  alias TireDispatch.Jobs
  alias TireDispatch.Payments

  require Logger

  @doc """
  Handles incoming Stripe webhook events.

  Verifies the webhook signature and processes the event based on its type.
  Currently handles:
  - checkout.session.completed: Payment confirmation for driver payments

  ## Parameters

    * `conn` - Plug.Conn struct
    * `params` - Webhook payload from Stripe

  ## Returns

    * 200 OK response if webhook is processed successfully
    * 400 Bad Request if signature verification fails
    * 500 Internal Server Error if processing fails
  """
  def stripe_webhook(conn, _params) do
    # Get the raw body for signature verification
    {:ok, raw_body, _conn} = Plug.Conn.read_body(conn)

    # Get the Stripe signature from headers
    stripe_signature = get_req_header(conn, "stripe-signature") |> List.first()

    case verify_webhook_signature(raw_body, stripe_signature) do
      {:ok, event} ->
        handle_stripe_event(event)
        send_resp(conn, 200, "Webhook received")

      {:error, reason} ->
        Logger.error("Stripe webhook signature verification failed", %{
          reason: inspect(reason)
        })

        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid signature"})
    end
  end

  # Private helper functions

  defp verify_webhook_signature(raw_body, signature) do
    webhook_secret = get_webhook_secret()

    case Stripe.Webhook.construct_event(raw_body, signature, webhook_secret) do
      {:ok, event} ->
        {:ok, event}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_webhook_secret do
    Application.get_env(:stripity_stripe, :webhook_secret) ||
      System.get_env("STRIPE_WEBHOOK_SECRET") ||
      raise "STRIPE_WEBHOOK_SECRET not configured"
  end

  defp handle_stripe_event(%Stripe.Event{type: "checkout.session.completed"} = event) do
    Logger.info("Processing checkout.session.completed event", %{
      event_id: event.id
    })

    session = event.data.object

    # Extract job_id from client_reference_id or metadata
    job_id = session.client_reference_id || get_in(session, [:metadata, "job_id"])
    payment_intent_id = session.payment_intent

    if job_id do
      process_payment_confirmation(job_id, payment_intent_id, session)
    else
      Logger.error("No job_id found in checkout session", %{
        session_id: session.id
      })
    end
  end

  defp handle_stripe_event(%Stripe.Event{type: event_type} = event) do
    Logger.info("Received unhandled Stripe event", %{
      event_type: event_type,
      event_id: event.id
    })

    :ok
  end

  defp process_payment_confirmation(job_id, payment_intent_id, session) do
    Logger.info("Processing payment confirmation", %{
      job_id: job_id,
      payment_intent_id: payment_intent_id,
      session_id: session.id
    })

    with {:ok, job} <- Jobs.get_job(job_id),
         {:ok, transaction} <- get_pending_transaction(job_id),
         {:ok, _transaction} <-
           Payments.mark_payment_completed(transaction, payment_intent_id) do
      Logger.info("Payment confirmed successfully", %{
        job_id: job_id,
        transaction_id: transaction.id,
        payment_intent_id: payment_intent_id
      })

      # Broadcast payment confirmation to driver
      broadcast_payment_confirmed(job, transaction)

      :ok
    else
      {:error, :not_found} ->
        Logger.error("Job not found for payment confirmation", %{
          job_id: job_id
        })

        :error

      {:error, :payment_not_found} ->
        Logger.error("No pending payment transaction found", %{
          job_id: job_id
        })

        :error

      {:error, reason} ->
        Logger.error("Failed to process payment confirmation", %{
          job_id: job_id,
          reason: inspect(reason)
        })

        :error
    end
  end

  defp get_pending_transaction(job_id) do
    case TireDispatch.Repo.get_by(TireDispatch.Payments.Transaction,
           job_id: job_id,
           type: :payment,
           status: :pending
         ) do
      nil -> {:error, :payment_not_found}
      transaction -> {:ok, transaction}
    end
  end

  defp broadcast_payment_confirmed(job, transaction) do
    TireDispatchWeb.Endpoint.broadcast(
      "jobs:#{job.id}",
      "payment_confirmed",
      %{
        job_id: job.id,
        transaction_id: transaction.id,
        amount_cents: transaction.amount_cents
      }
    )

    TireDispatchWeb.Endpoint.broadcast(
      "driver:#{job.driver_id}:jobs",
      "payment_confirmed",
      %{
        job_id: job.id,
        transaction_id: transaction.id,
        amount_cents: transaction.amount_cents
      }
    )

    :ok
  end
end
