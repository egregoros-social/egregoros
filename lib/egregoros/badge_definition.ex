defmodule Egregoros.BadgeDefinition do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, FlakeId.Ecto.Type, autogenerate: true}
  @foreign_key_type FlakeId.Ecto.Type

  @fields ~w(badge_type name description narrative image_url disabled)a
  @required_fields ~w(badge_type name description narrative disabled)a

  schema "badge_definitions" do
    field :badge_type, :string
    field :name, :string
    field :description, :string
    field :narrative, :string
    field :image_url, :string
    field :disabled, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(badge_definition, attrs) do
    badge_definition
    |> cast(attrs, @fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:badge_type)
  end
end
