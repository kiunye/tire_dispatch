defmodule TireDispatch.Repo.Migrations.AddRoleAndPhoneToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :role, :string, null: false, default: "driver"
      add :phone_number, :string
      add :is_active, :boolean, default: true, null: false
    end

    create index(:users, [:role])
  end
end
