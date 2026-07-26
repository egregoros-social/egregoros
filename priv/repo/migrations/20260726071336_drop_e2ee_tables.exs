defmodule Egregoros.Repo.Migrations.DropE2eeTables do
  use Ecto.Migration

  # End-to-end encrypted DMs were removed ahead of the Pleroma-compatibility
  # migration. `down/0` recreates the tables in their last known shape (flake
  # id primary keys) so the rollback path stays usable, but the key material
  # itself is gone for good.

  def up do
    drop_if_exists table(:e2ee_key_wrappers)
    drop_if_exists table(:e2ee_keys)
    drop_if_exists table(:e2ee_actor_keys)
  end

  def down do
    create table(:e2ee_keys, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
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

    create table(:e2ee_key_wrappers, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :kid, :string, null: false
      add :type, :string, null: false
      add :wrapped_private_key, :binary, null: false
      add :params, :map, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:e2ee_key_wrappers, [:user_id])
    create index(:e2ee_key_wrappers, [:user_id, :kid])
    create unique_index(:e2ee_key_wrappers, [:user_id, :kid, :type])

    create table(:e2ee_actor_keys, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :actor_ap_id, :string, null: false
      add :kid, :string, null: false
      add :jwk, :map, null: false
      add :fingerprint, :string
      add :position, :integer, null: false
      add :present, :boolean, null: false, default: true
      add :fetched_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:e2ee_actor_keys, [:actor_ap_id, :kid])
    create index(:e2ee_actor_keys, [:actor_ap_id, :present, :position])
  end
end
