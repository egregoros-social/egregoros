defmodule PleromaRedux.Relationships do
  import Ecto.Query, only: [from: 2]

  alias PleromaRedux.Relationship
  alias PleromaRedux.Repo

  def upsert_relationship(attrs) when is_map(attrs) do
    %Relationship{}
    |> Relationship.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:activity_ap_id, :updated_at]},
      conflict_target: [:type, :actor, :object]
    )
  end

  def get(id) when is_integer(id), do: Repo.get(Relationship, id)

  def get_by_type_actor_object(type, actor, object)
      when is_binary(type) and is_binary(actor) and is_binary(object) do
    Repo.get_by(Relationship, type: type, actor: actor, object: object)
  end

  def delete_by_type_actor_object(type, actor, object)
      when is_binary(type) and is_binary(actor) and is_binary(object) do
    from(r in Relationship, where: r.type == ^type and r.actor == ^actor and r.object == ^object)
    |> Repo.delete_all()
  end

  def list_follows_to(object_ap_id) when is_binary(object_ap_id) do
    from(r in Relationship, where: r.type == "Follow" and r.object == ^object_ap_id)
    |> Repo.all()
  end

  def list_follows_by_actor(actor_ap_id) when is_binary(actor_ap_id) do
    from(r in Relationship, where: r.type == "Follow" and r.actor == ^actor_ap_id)
    |> Repo.all()
  end

  def count_by_type_object(type, object_ap_id)
      when is_binary(type) and is_binary(object_ap_id) do
    from(r in Relationship, where: r.type == ^type and r.object == ^object_ap_id)
    |> Repo.aggregate(:count, :id)
  end
end
