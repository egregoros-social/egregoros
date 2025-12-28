defmodule Egregoros.Repo.Migrations.AddEmojisToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :emojis, {:array, :map}, null: false, default: []
    end
  end
end
