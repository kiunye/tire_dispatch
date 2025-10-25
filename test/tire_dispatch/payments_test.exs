defmodule TireDispatch.PaymentsTest do
  use TireDispatch.DataCase, async: true

  alias TireDispatch.Payments
  alias TireDispatch.Payments.Transaction

  describe "create_payment/4" do
    test "creates a payment transaction with valid attributes" do
      job = insert(:job)
      driver = job.driver

      assert {:ok, %Transaction{} = transaction} =
               Payments.create_payment(job.id, 3500, driver.id, :stripe)

      assert transaction.job_id == job.id
      assert transaction.driver_id == driver.id
      assert transaction.amount_cents == 3500
      assert transaction.type == :payment
      assert transaction.status == :pending
      assert transaction.payment_method == :stripe
      assert transaction.currency == "usd"
    end

    test "creates an MPESA payment transaction" do
      job = insert(:job)
      driver = job.driver

      assert {:ok, %Transaction{} = transaction} =
               Payments.create_payment(job.id, 3500, driver.id, :mpesa)

      assert transaction.payment_method == :mpesa
    end
  end

  describe "get_transaction!/1 and get_transaction/1" do
    test "get_transaction!/1 returns transaction when it exists" do
      transaction = insert(:transaction)
      assert %Transaction{} = found = Payments.get_transaction!(transaction.id)
      assert found.id == transaction.id
    end

    test "get_transaction!/1 raises when transaction doesn't exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Payments.get_transaction!(999_999)
      end
    end

    test "get_transaction/1 returns transaction with preloaded associations" do
      transaction = insert(:transaction)
      assert {:ok, %Transaction{} = found} = Payments.get_transaction(transaction.id)
      assert found.id == transaction.id
      assert Ecto.assoc_loaded?(found.job)
      assert Ecto.assoc_loaded?(found.driver)
    end

    test "get_transaction/1 returns error when not found" do
      assert {:error, :not_found} = Payments.get_transaction(Ecto.UUID.generate())
    end
  end

  describe "mark_payment_completed/2" do
    test "marks payment as completed with external transaction ID" do
      transaction = insert(:transaction, status: :pending)
      external_id = "ch_test_123"

      assert {:ok, %Transaction{} = updated} =
               Payments.mark_payment_completed(transaction, external_id)

      assert updated.status == :completed
      assert updated.external_transaction_id == external_id
    end
  end

  describe "mark_payment_failed/2" do
    test "marks payment as failed with error message" do
      transaction = insert(:transaction, status: :pending)
      error_message = "Card declined"

      assert {:ok, %Transaction{} = updated} =
               Payments.mark_payment_failed(transaction, error_message)

      assert updated.status == :failed
      assert updated.error_message == error_message
    end
  end

  describe "list_pending_payouts/0" do
    test "returns only pending payout transactions" do
      pending_payout = insert(:payout, status: :pending)
      insert(:completed_payout)
      insert(:transaction, type: :payment)

      payouts = Payments.list_pending_payouts()

      assert length(payouts) == 1
      assert hd(payouts).id == pending_payout.id
    end

    test "returns empty list when no pending payouts exist" do
      insert(:completed_payout)
      insert(:transaction)

      assert Payments.list_pending_payouts() == []
    end
  end

  describe "process_provider_payout/1" do
    test "creates payout transaction for completed job" do
      job = insert(:completed_job)
      insert(:completed_payment, job: job)

      assert {:ok, %Transaction{} = payout} = Payments.process_provider_payout(job.id)

      assert payout.type == :payout
      assert payout.status == :pending
      assert payout.job_id == job.id
      assert payout.provider_id == job.provider_id
      # Payout should be 85% of job amount (15% commission)
      assert payout.amount_cents == div(job.final_price_cents * 85, 100)
    end

    test "returns error when job is not completed" do
      job = insert(:accepted_job)

      assert {:error, :job_not_completed} = Payments.process_provider_payout(job.id)
    end

    test "returns error when no provider assigned" do
      job = insert(:job, status: :completed, provider_id: nil)

      assert {:error, :no_provider_assigned} = Payments.process_provider_payout(job.id)
    end

    test "returns error when payout already processed" do
      job = insert(:completed_job)
      insert(:completed_payment, job: job)
      insert(:payout, job: job)

      assert {:error, :payout_already_processed} = Payments.process_provider_payout(job.id)
    end

    test "returns error when payment not found" do
      job = insert(:completed_job)

      assert {:error, :payment_not_found} = Payments.process_provider_payout(job.id)
    end
  end

  describe "get_payment_transaction_for_job/1" do
    test "returns payment transaction for job" do
      job = insert(:job)
      payment = insert(:completed_payment, job: job)

      assert {:ok, %Transaction{} = found} = Payments.get_payment_transaction_for_job(job.id)
      assert found.id == payment.id
    end

    test "returns error when no payment exists" do
      job = insert(:job)

      assert {:error, :not_found} = Payments.get_payment_transaction_for_job(job.id)
    end
  end

  describe "list_job_transactions/1" do
    test "returns all transactions for a job" do
      job = insert(:completed_job)
      payment = insert(:completed_payment, job: job)
      payout = insert(:payout, job: job)
      insert(:transaction)

      transactions = Payments.list_job_transactions(job.id)

      assert length(transactions) == 2
      transaction_ids = Enum.map(transactions, & &1.id)
      assert payment.id in transaction_ids
      assert payout.id in transaction_ids
    end
  end

  describe "get_transaction_by_mpesa_checkout_request_id/1" do
    test "returns transaction with matching checkout request ID" do
      transaction = insert(:mpesa_payment, mpesa_checkout_request_id: "ws_CO_123")

      found = Payments.get_transaction_by_mpesa_checkout_request_id("ws_CO_123")

      assert found.id == transaction.id
    end

    test "returns nil when no matching transaction exists" do
      assert is_nil(Payments.get_transaction_by_mpesa_checkout_request_id("ws_CO_999"))
    end
  end

  describe "update_transaction/2" do
    test "updates transaction with new attributes" do
      transaction = insert(:transaction)

      assert {:ok, %Transaction{} = updated} =
               Payments.update_transaction(transaction, %{notes: "Updated notes"})

      assert updated.notes == "Updated notes"
    end
  end

  describe "refund_payment/2" do
    test "returns error for non-payment transaction" do
      payout = insert(:payout)

      assert {:error, :not_a_payment_transaction} =
               Payments.refund_payment(payout, "test reason")
    end

    test "returns error for non-completed payment" do
      payment = insert(:transaction, type: :payment, status: :pending)

      assert {:error, :payment_not_completed} = Payments.refund_payment(payment, "test reason")
    end

    test "returns error when refund already exists" do
      payment = insert(:completed_payment)
      insert(:refund, reference_transaction: payment)

      assert {:error, :refund_already_processed} =
               Payments.refund_payment(payment, "test reason")
    end

    test "returns error when no external transaction ID" do
      payment =
        insert(:completed_payment, external_transaction_id: nil)

      assert {:error, :no_external_transaction_id} =
               Payments.refund_payment(payment, "test reason")
    end
  end
end
