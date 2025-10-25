defmodule TireDispatch.Factory do
  @moduledoc """
  ExMachina factory for generating test data.
  """
  use ExMachina.Ecto, repo: TireDispatch.Repo

  alias TireDispatch.Jobs.Job
  alias TireDispatch.Payments.Transaction
  alias TireDispatch.Providers.Provider
  alias TireDispatch.Users.User

  # User Factories

  def user_factory do
    %User{
      email: sequence(:email, &"user#{&1}@example.com"),
      hashed_password: Bcrypt.hash_pwd_salt("password123456"),
      confirmed_at: DateTime.utc_now(:second),
      role: :driver,
      phone_number: sequence(:phone, &"+254712#{String.pad_leading(Integer.to_string(&1), 6, "0")}"),
      is_active: true
    }
  end

  def driver_factory do
    struct!(
      user_factory(),
      %{role: :driver}
    )
  end

  def provider_user_factory do
    struct!(
      user_factory(),
      %{role: :provider}
    )
  end

  def admin_factory do
    struct!(
      user_factory(),
      %{role: :admin}
    )
  end

  def unconfirmed_user_factory do
    struct!(
      user_factory(),
      %{confirmed_at: nil}
    )
  end

  # Provider Factories

  def provider_factory do
    user = insert(:provider_user)

    %Provider{
      user_id: user.id,
      service_radius_km: 15,
      vehicle_type: :suv,
      rating: Decimal.new("4.5"),
      is_active: true,
      is_verified: true,
      is_premium: false,
      payout_method: :stripe,
      stripe_account_id: sequence(:stripe_account, &"acct_test_#{&1}"),
      latitude: -1.2921 + :rand.uniform() * 0.1,
      longitude: 36.8219 + :rand.uniform() * 0.1
    }
  end

  def unverified_provider_factory do
    struct!(
      provider_factory(),
      %{is_verified: false}
    )
  end

  def premium_provider_factory do
    struct!(
      provider_factory(),
      %{
        is_premium: true,
        stripe_subscription_id: sequence(:subscription, &"sub_test_#{&1}")
      }
    )
  end

  def mpesa_provider_factory do
    struct!(
      provider_factory(),
      %{
        payout_method: :mpesa,
        stripe_account_id: nil,
        mpesa_phone_number: "+254712345678"
      }
    )
  end

  # Job Factories

  def job_factory do
    driver_location = %Geo.Point{
      coordinates: {36.8219 + :rand.uniform() * 0.1, -1.2921 + :rand.uniform() * 0.1},
      srid: 4326
    }

    %Job{
      service_type: :flat_repair,
      status: :open,
      urgency_tier: :standard,
      vehicle_type: :compact,
      driver_location: driver_location,
      estimated_price_cents: 3500,
      issue_notes: "Flat tire on highway",
      photos: [],
      driver: build(:driver)
    }
  end

  def accepted_job_factory do
    provider_location = %Geo.Point{
      coordinates: {36.8219 + :rand.uniform() * 0.05, -1.2921 + :rand.uniform() * 0.05},
      srid: 4326
    }

    struct!(
      job_factory(),
      %{
        status: :accepted,
        provider: build(:provider_user),
        provider_location: provider_location
      }
    )
  end

  def en_route_job_factory do
    struct!(
      accepted_job_factory(),
      %{status: :en_route}
    )
  end

  def on_site_job_factory do
    struct!(
      accepted_job_factory(),
      %{status: :on_site}
    )
  end

  def completed_job_factory do
    struct!(
      accepted_job_factory(),
      %{
        status: :completed,
        before_photo_url: "https://s3.amazonaws.com/test-bucket/before.jpg",
        after_photo_url: "https://s3.amazonaws.com/test-bucket/after.jpg",
        final_price_cents: 3500,
        completed_at: DateTime.utc_now(:microsecond)
      }
    )
  end

  def cancelled_job_factory do
    struct!(
      job_factory(),
      %{
        status: :cancelled,
        cancellation_reason: "Driver cancelled request"
      }
    )
  end

  def rush_job_factory do
    struct!(
      job_factory(),
      %{
        urgency_tier: :rush,
        estimated_price_cents: 4550
      }
    )
  end

  def emergency_job_factory do
    struct!(
      job_factory(),
      %{
        urgency_tier: :emergency,
        estimated_price_cents: 5600
      }
    )
  end

  # Transaction Factories

  def transaction_factory do
    %Transaction{
      amount_cents: 3500,
      currency: "usd",
      type: :payment,
      status: :pending,
      payment_method: :stripe,
      job: build(:job),
      driver: build(:driver)
    }
  end

  def completed_payment_factory do
    struct!(
      transaction_factory(),
      %{
        status: :completed,
        external_transaction_id: sequence(:stripe_charge, &"ch_test_#{&1}")
      }
    )
  end

  def failed_payment_factory do
    struct!(
      transaction_factory(),
      %{
        status: :failed,
        error_message: "Card declined"
      }
    )
  end

  def mpesa_payment_factory do
    struct!(
      transaction_factory(),
      %{
        payment_method: :mpesa,
        mpesa_checkout_request_id: sequence(:checkout_request, &"ws_CO_#{&1}"),
        mpesa_phone_number: "+254712345678"
      }
    )
  end

  def payout_factory do
    %Transaction{
      amount_cents: 2975,
      currency: "usd",
      type: :payout,
      status: :pending,
      payment_method: :stripe,
      job: build(:completed_job),
      provider: build(:provider_user)
    }
  end

  def completed_payout_factory do
    struct!(
      payout_factory(),
      %{
        status: :completed,
        external_transaction_id: sequence(:stripe_transfer, &"tr_test_#{&1}")
      }
    )
  end

  def mpesa_payout_factory do
    struct!(
      payout_factory(),
      %{
        payment_method: :mpesa,
        mpesa_phone_number: "+254712345678"
      }
    )
  end

  def refund_factory do
    %Transaction{
      amount_cents: 3500,
      currency: "usd",
      type: :refund,
      status: :pending,
      payment_method: :stripe,
      job: build(:completed_job),
      driver: build(:driver),
      reference_transaction: build(:completed_payment)
    }
  end

  def completed_refund_factory do
    struct!(
      refund_factory(),
      %{
        status: :completed,
        external_transaction_id: sequence(:stripe_refund, &"re_test_#{&1}")
      }
    )
  end

  # Pricing Rule Factories

  def pricing_rule_factory do
    %TireDispatch.Pricing.PricingRule{
      rule_type: :base_rate,
      name: sequence(:rule_name, &"Pricing Rule #{&1}"),
      value: Decimal.new("100.00"),
      active: true,
      conditions: %{}
    }
  end

  # Analytics Factories

  def daily_stat_factory do
    %TireDispatch.Analytics.DailyStat{
      date: Date.utc_today(),
      total_jobs: 10,
      completed_jobs: 8,
      cancelled_jobs: 2,
      total_revenue_cents: 100_000,
      average_response_time_minutes: 15.5,
      provider_utilization_percent: 75.0,
      average_job_value_cents: 12_500
    }
  end
end
