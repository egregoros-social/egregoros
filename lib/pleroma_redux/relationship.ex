defmodule PleromaRedux.Relationship do
  use Ecto.Schema

  import Ecto.Changeset

  schema "relationships" do
    field :type, :string
    field :actor, :string
    field :object, :string
    field :activity_ap_id, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(relationship, attrs) do
    relationship
    |> cast(attrs, [:type, :actor, :object, :activity_ap_id])
    |> validate_required([:type, :actor, :object, :activity_ap_id])
    |> unique_constraint([:type, :actor, :object], name: :relationships_type_actor_object_index)
  end
end

