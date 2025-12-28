defmodule Egregoros.Repo.Migrations.MakeRelationshipActivityApIdNullable do
  use Ecto.Migration

  def change do
    alter table(:relationships) do
      modify :activity_ap_id, :string, null: true
    end
  end
end

