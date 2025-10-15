defmodule TireDispatch.Repo.Migrations.CreateTransactions do
  use Ecto.Migration

  def change do
    create table(:transactions) do
      add :amount_cents, :integer, null: false
      add :currency, :string, default: "usd", null: false
      add :type, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :stripe_transaction_id, :string
      add :error_message, :text
      add :notes, :text

      # Foreign keys
      add :job_id, references(:jobs, on_delete: :nilify_all)
      add :driver_id, references(:users, on_delete: :nilify_all)
      add :provider_id, references(:users, on_delete: :nilify_all)
      add :reference_transaction_id, references(:transactions, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    # Indexes
    create index(:transactions, [:job_id])
    create index(:transactions, [:stripe_transaction_id])
    create index(:transactions, [:type])
    create index(:transactions, [:status])
  end
end
