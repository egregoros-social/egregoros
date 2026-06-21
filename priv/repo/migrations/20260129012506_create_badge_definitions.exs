defmodule Egregoros.Repo.Migrations.CreateBadgeDefinitions do
  use Ecto.Migration

  def up do
    create table(:badge_definitions, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :badge_type, :string, null: false
      add :name, :string, null: false
      add :description, :text, null: false
      add :narrative, :text, null: false
      add :image_url, :string
      add :disabled, :boolean, null: false, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:badge_definitions, [:badge_type])

    flush()

    {:ok, _} = Application.ensure_all_started(:flake_id)

    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    repo().insert_all("badge_definitions", [
      %{
        id: FlakeId.from_string(FlakeId.get()),
        badge_type: "Donator",
        name: "Donator",
        description: "Awarded to users who have financially supported the instance.",
        narrative: "Make any monetary donation to support the instance.",
        disabled: false,
        inserted_at: now,
        updated_at: now
      },
      %{
        id: FlakeId.from_string(FlakeId.get()),
        badge_type: "VIP",
        name: "VIP",
        description: "Awarded to users granted VIP status by staff.",
        narrative: "Granted by the server staff.",
        disabled: false,
        inserted_at: now,
        updated_at: now
      },
      %{
        id: FlakeId.from_string(FlakeId.get()),
        badge_type: "Founder",
        name: "Founder",
        description: "Awarded to early supporters of the instance.",
        narrative: "Joined during the founding period.",
        disabled: false,
        inserted_at: now,
        updated_at: now
      }
    ])
  end

  def down do
    drop table(:badge_definitions)
  end
end
