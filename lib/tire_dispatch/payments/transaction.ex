defmodule TireDispatch.Payments.Transaction do
  @moduledoc """
  Transaction schema for tracking payments, payouts, and refunds.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "transactions" do
    field :amount_cents, :integer
    field :currency, :string, default: "usd"
    field :type, Ecto.Enum, values: [:payment, :payout, :refund]
    field :status, Ecto.Enum, values: [:pending, :completed, :failed], default: :pending
    field :payment_method, Ecto.Enum, values: [:stripe, :mpesa]
    field :external_transaction_id, :string
    field :mpesa_checkout_request_id, :string
    field :mpesa_phone_number, :string
    field :error_message, :string
    field :notes, :string

    belongs_to :job, TireDispatch.Jobs.Job
    belongs_to :driver, TireDispatch.Users.User
    belongs_to :provider, TireDispatch.Users.User
    belongs_to :reference_transaction, TireDispatch.Payments.Transaction

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a transaction.
  """
  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [
      :amount_cents,
      :currency,
      :type,
      :status,
      :payment_method,
      :external_transaction_id,
      :mpesa_checkout_request_id,
      :mpesa_phone_number,
      :error_message,
      :notes,
      :job_id,
      :driver_id,
      :provider_id,
      :reference_transaction_id
    ])
    |> validate_required([:amount_cents, :type, :status])
    |> validate_inclusion(:type, [:payment, :payout, :refund])
    |> validate_inclusion(:status, [:pending, :completed, :failed])
    |> validate_number(:amount_cents, greater_than: 0)
    |> validate_length(:currency, is: 3)
    |> foreign_key_constraint(:job_id)
    |> foreign_key_constraint(:driver_id)
    |> foreign_key_constraint(:provider_id)
    |> foreign_key_constraint(:reference_transaction_id)
  end

  @doc """
  Changeset for updating transaction status.
  """
  def status_changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [:status, :external_transaction_id, :error_message])
    |> validate_required([:status])
    |> validate_inclusion(:status, [:pending, :completed, :failed])
  end
end
