defmodule TireDispatch.Repo.Migrations.AddPayoutFieldsToProviders do
  use Ecto.Migration

  def change do
    alter table(:providers) do
      add :payout_method, :string, default: "stripe"
      add :mpesa_phone_number, :string
      add :stripe_subscription_id, :string
    end

    create index(:providers, [:payout_method])
  end
end
