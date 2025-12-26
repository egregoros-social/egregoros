defmodule Egregoros.Relationships do
  import Ecto.Query, only: [from: 2]

  alias Egregoros.Relationship
  alias Egregoros.Repo

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

  def list_follows_by_actor_for_objects(actor_ap_id, object_ap_ids)
      when is_binary(actor_ap_id) and is_list(object_ap_ids) do
    object_ap_ids =
      object_ap_ids
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    if object_ap_ids == [] do
      []
    else
      from(r in Relationship,
        where: r.type == "Follow" and r.actor == ^actor_ap_id and r.object in ^object_ap_ids
      )
      |> Repo.all()
    end
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

  def count_by_type_objects(type, object_ap_ids)
      when is_binary(type) and is_list(object_ap_ids) do
    object_ap_ids = normalize_ap_ids(object_ap_ids)

    if object_ap_ids == [] do
      %{}
    else
      from(r in Relationship,
        where: r.type == ^type and r.object in ^object_ap_ids,
        group_by: r.object,
        select: {r.object, count(r.id)}
      )
      |> Repo.all()
      |> Map.new()
    end
  end

  def count_by_type_actors(type, actor_ap_ids)
      when is_binary(type) and is_list(actor_ap_ids) do
    actor_ap_ids = normalize_ap_ids(actor_ap_ids)

    if actor_ap_ids == [] do
      %{}
    else
      from(r in Relationship,
        where: r.type == ^type and r.actor in ^actor_ap_ids,
        group_by: r.actor,
        select: {r.actor, count(r.id)}
      )
      |> Repo.all()
      |> Map.new()
    end
  end

  def count_by_types_objects(types, object_ap_ids)
      when is_list(types) and is_list(object_ap_ids) do
    types =
      types
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    object_ap_ids = normalize_ap_ids(object_ap_ids)

    if types == [] or object_ap_ids == [] do
      %{}
    else
      from(r in Relationship,
        where: r.type in ^types and r.object in ^object_ap_ids,
        group_by: [r.object, r.type],
        select: {r.object, r.type, count(r.id)}
      )
      |> Repo.all()
      |> Enum.reduce(%{}, fn {object, type, count}, acc ->
        Map.update(acc, object, %{type => count}, &Map.put(&1, type, count))
      end)
    end
  end

  def list_by_types_actor_objects(types, actor_ap_id, object_ap_ids)
      when is_list(types) and is_binary(actor_ap_id) and is_list(object_ap_ids) do
    types =
      types
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    object_ap_ids = normalize_ap_ids(object_ap_ids)

    if types == [] or object_ap_ids == [] do
      MapSet.new()
    else
      from(r in Relationship,
        where: r.type in ^types and r.actor == ^actor_ap_id and r.object in ^object_ap_ids,
        select: {r.type, r.object}
      )
      |> Repo.all()
      |> MapSet.new()
    end
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

  def emoji_reaction_counts_for_objects(object_ap_ids) when is_list(object_ap_ids) do
    object_ap_ids = normalize_ap_ids(object_ap_ids)

    if object_ap_ids == [] do
      %{}
    else
      from(r in Relationship,
        where: r.object in ^object_ap_ids and like(r.type, "EmojiReact:%"),
        group_by: [r.object, r.type],
        select: {r.object, r.type, count(r.id)}
      )
      |> Repo.all()
      |> Enum.reduce(%{}, fn {object, type, count}, acc ->
        Map.update(acc, object, %{type => count}, &Map.put(&1, type, count))
      end)
    end
  end

  def emoji_reactions_by_actor_for_objects(actor_ap_id, object_ap_ids)
      when is_binary(actor_ap_id) and is_list(object_ap_ids) do
    object_ap_ids = normalize_ap_ids(object_ap_ids)

    if object_ap_ids == [] do
      MapSet.new()
    else
      from(r in Relationship,
        where:
          r.actor == ^actor_ap_id and r.object in ^object_ap_ids and like(r.type, "EmojiReact:%"),
        select: {r.type, r.object}
      )
      |> Repo.all()
      |> MapSet.new()
    end
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

  defp normalize_ap_ids(list) when is_list(list) do
    list
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end
end
