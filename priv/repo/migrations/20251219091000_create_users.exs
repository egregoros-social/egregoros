defmodule PleromaRedux.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :nickname, :text, null: false
      add :ap_id, :text, null: false
      add :inbox, :text, null: false
      add :outbox, :text, null: false
      add :public_key, :text, null: false
      add :private_key, :text, null: false
      add :local, :boolean, null: false, default: true

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:ap_id])
    create unique_index(:users, [:nickname])
  end
end
