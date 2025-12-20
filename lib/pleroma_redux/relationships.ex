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

  def delete_all_for_object(object_ap_id) when is_binary(object_ap_id) do
    from(r in Relationship, where: r.object == ^object_ap_id)
    |> Repo.delete_all()
  end

  def list_follows_to(object_ap_id) when is_binary(object_ap_id) do
    from(r in Relationship, where: r.type == "Follow" and r.object == ^object_ap_id)
    |> Repo.all()
  end

  def list_follows_to(object_ap_id, opts) when is_binary(object_ap_id) and is_list(opts) do
    limit = opts |> Keyword.get(:limit, 40) |> normalize_limit()
    max_id = Keyword.get(opts, :max_id)

    from(r in Relationship,
      where: r.type == "Follow" and r.object == ^object_ap_id,
      order_by: [desc: r.id],
      limit: ^limit
    )
    |> maybe_where_max_id(max_id)
    |> Repo.all()
  end

  def list_follows_by_actor(actor_ap_id) when is_binary(actor_ap_id) do
    from(r in Relationship, where: r.type == "Follow" and r.actor == ^actor_ap_id)
    |> Repo.all()
  end

  def list_follows_by_actor(actor_ap_id, opts) when is_binary(actor_ap_id) and is_list(opts) do
    limit = opts |> Keyword.get(:limit, 40) |> normalize_limit()
    max_id = Keyword.get(opts, :max_id)

    from(r in Relationship,
      where: r.type == "Follow" and r.actor == ^actor_ap_id,
      order_by: [desc: r.id],
      limit: ^limit
    )
    |> maybe_where_max_id(max_id)
    |> Repo.all()
  end

  def count_by_type_object(type, object_ap_id)
      when is_binary(type) and is_binary(object_ap_id) do
    from(r in Relationship, where: r.type == ^type and r.object == ^object_ap_id)
    |> Repo.aggregate(:count, :id)
  end

  def count_by_type_actor(type, actor_ap_id) when is_binary(type) and is_binary(actor_ap_id) do
    from(r in Relationship, where: r.type == ^type and r.actor == ^actor_ap_id)
    |> Repo.aggregate(:count, :id)
  end

  def list_by_type_object(type, object_ap_id, limit \\ 40)
      when is_binary(type) and is_binary(object_ap_id) and is_integer(limit) do
    limit =
      limit
      |> max(1)
      |> min(80)

    from(r in Relationship,
      where: r.type == ^type and r.object == ^object_ap_id,
      order_by: [desc: r.id],
      limit: ^limit
    )
    |> Repo.all()
  end

  def emoji_reaction_counts(object_ap_id) when is_binary(object_ap_id) do
    from(r in Relationship,
      where: r.object == ^object_ap_id and like(r.type, "EmojiReact:%"),
      group_by: r.type,
      select: {r.type, count(r.id)}
    )
    |> Repo.all()
  end

  defp maybe_where_max_id(query, max_id) when is_integer(max_id) and max_id > 0 do
    from(r in query, where: r.id < ^max_id)
  end

  defp maybe_where_max_id(query, _max_id), do: query

  defp normalize_limit(limit) when is_integer(limit) do
    limit
    |> max(1)
    |> min(80)
  end

  defp normalize_limit(_), do: 40
end
