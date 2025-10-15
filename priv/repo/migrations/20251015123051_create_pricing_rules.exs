defmodule TireDispatch.Repo.Migrations.CreatePricingRules do
  use Ecto.Migration

  def change do
    create table(:pricing_rules) do
      add :rule_type, :string, null: false
      add :name, :string, null: false
      add :value, :decimal, precision: 10, scale: 2, null: false
      add :conditions, :map, default: %{}
      add :active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Indexes
    create index(:pricing_rules, [:rule_type])
    create index(:pricing_rules, [:active])
  end
end
