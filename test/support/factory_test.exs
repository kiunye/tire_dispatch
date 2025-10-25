defmodule TireDispatch.FactoryTest do
  @moduledoc """
  Tests to verify that all factories work correctly.
  """
  use TireDispatch.DataCase

  describe "user factories" do
    test "user_factory creates a valid user" do
      user = insert(:user)
      assert user.id
      assert user.email
      assert user.hashed_password
      assert user.role == :driver
    end

    test "driver_factory creates a driver user" do
      driver = insert(:driver)
      assert driver.role == :driver
    end

    test "provider_user_factory creates a provider user" do
      provider_user = insert(:provider_user)
      assert provider_user.role == :provider
    end

    test "admin_factory creates an admin user" do
      admin = insert(:admin)
      assert admin.role == :admin
    end
  end

  describe "provider factories" do
    test "provider_factory creates a valid provider" do
      provider = insert(:provider)
      assert provider.id
      assert provider.user_id
      assert provider.service_radius_km == 15
      assert provider.is_verified
    end

    test "unverified_provider_factory creates an unverified provider" do
      provider = insert(:unverified_provider)
      refute provider.is_verified
    end

    test "premium_provider_factory creates a premium provider" do
      provider = insert(:premium_provider)
      assert provider.is_premium
      assert provider.stripe_subscription_id
    end

    test "mpesa_provider_factory creates a provider with MPESA payout" do
      provider = insert(:mpesa_provider)
      assert provider.payout_method == :mpesa
      assert provider.mpesa_phone_number
      refute provider.stripe_account_id
    end
  end

  describe "job factories" do
    test "job_factory creates a valid job" do
      job = insert(:job)
      assert job.id
      assert job.driver_id
      assert job.status == :open
      assert job.service_type == :flat_repair
      assert job.driver_location
    end

    test "accepted_job_factory creates an accepted job" do
      job = insert(:accepted_job)
      assert job.status == :accepted
      assert job.provider_id
      assert job.provider_location
    end

    test "completed_job_factory creates a completed job" do
      job = insert(:completed_job)
      assert job.status == :completed
      assert job.before_photo_url
      assert job.after_photo_url
      assert job.completed_at
    end

    test "rush_job_factory creates a rush job" do
      job = insert(:rush_job)
      assert job.urgency_tier == :rush
    end

    test "emergency_job_factory creates an emergency job" do
      job = insert(:emergency_job)
      assert job.urgency_tier == :emergency
    end
  end

  describe "transaction factories" do
    test "transaction_factory creates a valid transaction" do
      transaction = insert(:transaction)
      assert transaction.id
      assert transaction.amount_cents == 3500
      assert transaction.type == :payment
      assert transaction.status == :pending
    end

    test "completed_payment_factory creates a completed payment" do
      payment = insert(:completed_payment)
      assert payment.status == :completed
      assert payment.external_transaction_id
    end

    test "mpesa_payment_factory creates an MPESA payment" do
      payment = insert(:mpesa_payment)
      assert payment.payment_method == :mpesa
      assert payment.mpesa_checkout_request_id
      assert payment.mpesa_phone_number
    end

    test "payout_factory creates a valid payout" do
      payout = insert(:payout)
      assert payout.type == :payout
      assert payout.provider_id
    end

    test "refund_factory creates a valid refund" do
      refund = insert(:refund)
      assert refund.type == :refund
      assert refund.reference_transaction_id
    end
  end
end
