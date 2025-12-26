defmodule Egregoros.Repo.Migrations.CreateE2EETables do
  use Ecto.Migration

  def change do
    create table(:e2ee_keys) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :kid, :string, null: false
      add :public_key_jwk, :map, null: false
      add :fingerprint, :string, null: false
      add :active, :boolean, null: false, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:e2ee_keys, [:user_id])
    create unique_index(:e2ee_keys, [:user_id, :kid])

    create unique_index(:e2ee_keys, [:user_id],
             where: "active",
             name: :e2ee_keys_one_active_per_user
           )

    create table(:e2ee_key_wrappers) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :kid, :string, null: false
      add :type, :string, null: false
      add :wrapped_private_key, :binary, null: false
      add :params, :map, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:e2ee_key_wrappers, [:user_id])
    create index(:e2ee_key_wrappers, [:user_id, :kid])
    create unique_index(:e2ee_key_wrappers, [:user_id, :kid, :type])
  end
end
