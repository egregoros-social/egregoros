defmodule PleromaRedux.Repo.Migrations.CreateRelationships do
  use Ecto.Migration

  def change do
    create table(:relationships) do
      add :type, :string, null: false
      add :actor, :string, null: false
      add :object, :string, null: false
      add :activity_ap_id, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:relationships, [:type, :actor, :object],
             name: :relationships_type_actor_object_index
           )

    create index(:relationships, [:actor])
    create index(:relationships, [:object])
  end
end
