defmodule Egregoros.Repo.Migrations.AddMoveColumnsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :moved_to_ap_id, :text
      add :also_known_as, {:array, :text}, default: [], null: false
    end
  end
end
