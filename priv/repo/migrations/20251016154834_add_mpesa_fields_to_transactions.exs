defmodule TireDispatch.Repo.Migrations.AddMpesaFieldsToTransactions do
  use Ecto.Migration

  def change do
    alter table(:transactions) do
      add :payment_method, :string
      add :external_transaction_id, :string
      add :mpesa_checkout_request_id, :string
      add :mpesa_phone_number, :string
    end

    create index(:transactions, [:payment_method])
    create index(:transactions, [:external_transaction_id])
    create index(:transactions, [:mpesa_checkout_request_id])
  end
end
