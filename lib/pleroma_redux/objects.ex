defmodule PleromaRedux.Objects do
  import Ecto.Query, only: [from: 2]

  alias PleromaRedux.Object
  alias PleromaRedux.Relationships
  alias PleromaRedux.Repo

  def create_object(attrs) do
    %Object{}
    |> Object.changeset(attrs)
    |> Repo.insert()
  end

  def update_object(%Object{} = object, attrs) do
    object
    |> Object.changeset(attrs)
    |> Repo.update()
  end

  def upsert_object(attrs) do
    case create_object(attrs) do
      {:ok, %Object{} = object} ->
        {:ok, object}

      {:error, %Ecto.Changeset{} = changeset} ->
        if unique_ap_id_error?(changeset) do
          ap_id = Map.get(attrs, :ap_id) || Map.get(attrs, "ap_id")

          case get_by_ap_id(ap_id) do
            %Object{} = object -> {:ok, object}
            _ -> {:error, changeset}
          end
        else
          {:error, changeset}
        end
    end
  end

  def get_by_ap_id(nil), do: nil
  def get_by_ap_id(ap_id) when is_binary(ap_id), do: Repo.get_by(Object, ap_id: ap_id)

  def delete_object(%Object{} = object) do
    Repo.delete(object)
  end

  def get(id) when is_integer(id), do: Repo.get(Object, id)

  def get(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> Repo.get(Object, int)
      _ -> nil
    end
  end

  def get_by_type_actor_object(type, actor, object)
      when is_binary(type) and is_binary(actor) and is_binary(object) do
    from(o in Object,
      where: o.type == ^type and o.actor == ^actor and o.object == ^object,
      order_by: [desc: o.inserted_at, desc: o.id],
      limit: 1
    )
    |> Repo.one()
  end

  def get_emoji_react(actor, object, emoji)
      when is_binary(actor) and is_binary(object) and is_binary(emoji) do
    from(o in Object,
      where:
        o.type == "EmojiReact" and o.actor == ^actor and o.object == ^object and
          fragment("?->>'content' = ?", o.data, ^emoji),
      order_by: [desc: o.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  def count_emoji_reacts(object, emoji) when is_binary(object) and is_binary(emoji) do
    from(o in Object,
      where:
        o.type == "EmojiReact" and o.object == ^object and
          fragment("?->>'content' = ?", o.data, ^emoji)
    )
    |> Repo.aggregate(:count, :id)
  end

  def list_follows_to(object_ap_id) when is_binary(object_ap_id) do
    from(o in Object, where: o.type == "Follow" and o.object == ^object_ap_id)
    |> Repo.all()
  end

  def list_follows_by_actor(actor_ap_id) when is_binary(actor_ap_id) do
    from(o in Object, where: o.type == "Follow" and o.actor == ^actor_ap_id)
    |> Repo.all()
  end

  def list_notes, do: list_notes(limit: 20)

  def list_notes(limit) when is_integer(limit) do
    list_notes(limit: limit)
  end

  def list_notes(opts) when is_list(opts) do
    limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()
    max_id = Keyword.get(opts, :max_id)
    since_id = Keyword.get(opts, :since_id)

    from(o in Object,
      where: o.type == "Note",
      order_by: [desc: o.id],
      limit: ^limit
    )
    |> maybe_where_max_id(max_id)
    |> maybe_where_since_id(since_id)
    |> Repo.all()
  end

  def list_notes_by_hashtag(tag, opts \\ [])

  def list_notes_by_hashtag(tag, opts) when is_binary(tag) and is_list(opts) do
    tag =
      tag
      |> String.trim()
      |> String.trim_leading("#")

    if tag == "" do
      []
    else
      limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()
      max_id = Keyword.get(opts, :max_id)
      since_id = Keyword.get(opts, :since_id)

      pattern = "%#" <> tag <> "%"

      from(o in Object,
        where:
          o.type == "Note" and
            fragment("?->>'content' ILIKE ?", o.data, ^pattern),
        order_by: [desc: o.id],
        limit: ^limit
      )
      |> maybe_where_max_id(max_id)
      |> maybe_where_since_id(since_id)
      |> Repo.all()
    end
  end

  def list_notes_by_hashtag(_tag, _opts), do: []

  def search_notes(query, opts \\ [])

  def search_notes(query, opts) when is_binary(query) and is_list(opts) do
    query = String.trim(query)
    limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()

    if query == "" do
      []
    else
      pattern = "%" <> query <> "%"

      from(o in Object,
        where:
          o.type == "Note" and
            (fragment("?->>'content' ILIKE ?", o.data, ^pattern) or
               fragment("?->>'summary' ILIKE ?", o.data, ^pattern)),
        order_by: [desc: o.id],
        limit: ^limit
      )
      |> Repo.all()
    end
  end

  def search_notes(_query, _opts), do: []

  @status_types ~w(Note Announce)

  def list_public_statuses(opts \\ []) when is_list(opts) do
    limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()
    max_id = Keyword.get(opts, :max_id)
    since_id = Keyword.get(opts, :since_id)

    from(o in Object,
      where: o.type in ^@status_types,
      order_by: [desc: o.id],
      limit: ^limit
    )
    |> maybe_where_max_id(max_id)
    |> maybe_where_since_id(since_id)
    |> Repo.all()
  end

  def list_home_notes(actor_ap_id) when is_binary(actor_ap_id) do
    list_home_notes(actor_ap_id, limit: 20)
  end

  def list_home_notes(actor_ap_id, limit) when is_binary(actor_ap_id) and is_integer(limit) do
    list_home_notes(actor_ap_id, limit: limit)
  end

  def list_home_notes(actor_ap_id, opts) when is_binary(actor_ap_id) and is_list(opts) do
    limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()
    max_id = Keyword.get(opts, :max_id)
    since_id = Keyword.get(opts, :since_id)

    followed_actor_ids =
      actor_ap_id
      |> Relationships.list_follows_by_actor()
      |> Enum.map(& &1.object)
      |> Enum.filter(&is_binary/1)

    actor_ids = Enum.uniq([actor_ap_id | followed_actor_ids])

    from(o in Object,
      where: o.type == "Note" and o.actor in ^actor_ids,
      order_by: [desc: o.id],
      limit: ^limit
    )
    |> maybe_where_max_id(max_id)
    |> maybe_where_since_id(since_id)
    |> Repo.all()
  end

  def list_home_statuses(actor_ap_id) when is_binary(actor_ap_id) do
    list_home_statuses(actor_ap_id, limit: 20)
  end

  def list_home_statuses(actor_ap_id, opts) when is_binary(actor_ap_id) and is_list(opts) do
    limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()
    max_id = Keyword.get(opts, :max_id)
    since_id = Keyword.get(opts, :since_id)

    followed_actor_ids =
      actor_ap_id
      |> Relationships.list_follows_by_actor()
      |> Enum.map(& &1.object)
      |> Enum.filter(&is_binary/1)

    actor_ids = Enum.uniq([actor_ap_id | followed_actor_ids])

    from(o in Object,
      where: o.type in ^@status_types and o.actor in ^actor_ids,
      order_by: [desc: o.id],
      limit: ^limit
    )
    |> maybe_where_max_id(max_id)
    |> maybe_where_since_id(since_id)
    |> Repo.all()
  end

  def list_notes_by_actor(actor) when is_binary(actor), do: list_notes_by_actor(actor, limit: 20)

  def list_notes_by_actor(actor, limit) when is_binary(actor) and is_integer(limit) do
    list_notes_by_actor(actor, limit: limit)
  end

  def list_notes_by_actor(actor, opts) when is_binary(actor) and is_list(opts) do
    limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()
    max_id = Keyword.get(opts, :max_id)
    since_id = Keyword.get(opts, :since_id)

    from(o in Object,
      where: o.type == "Note" and o.actor == ^actor,
      order_by: [desc: o.id],
      limit: ^limit
    )
    |> maybe_where_max_id(max_id)
    |> maybe_where_since_id(since_id)
    |> Repo.all()
  end

  def list_statuses_by_actor(actor) when is_binary(actor),
    do: list_statuses_by_actor(actor, limit: 20)

  def list_statuses_by_actor(actor, opts) when is_binary(actor) and is_list(opts) do
    limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()
    max_id = Keyword.get(opts, :max_id)
    since_id = Keyword.get(opts, :since_id)

    from(o in Object,
      where: o.type in ^@status_types and o.actor == ^actor,
      order_by: [desc: o.id],
      limit: ^limit
    )
    |> maybe_where_max_id(max_id)
    |> maybe_where_since_id(since_id)
    |> Repo.all()
  end

  def count_notes_by_actor(actor) when is_binary(actor) do
    from(o in Object, where: o.type == "Note" and o.actor == ^actor)
    |> Repo.aggregate(:count, :id)
  end

  def count_by_type_object(type, object_ap_id) when is_binary(type) and is_binary(object_ap_id) do
    from(o in Object, where: o.type == ^type and o.object == ^object_ap_id)
    |> Repo.aggregate(:count, :id)
  end

  def thread_ancestors(object, limit \\ 50)

  def thread_ancestors(%Object{} = object, limit) when is_integer(limit) and limit > 0 do
    object
    |> do_thread_ancestors(MapSet.new([object.ap_id]), limit)
    |> Enum.reverse()
  end

  def thread_ancestors(_object, _limit), do: []

  defp do_thread_ancestors(%Object{} = object, visited, limit)
       when is_integer(limit) and limit > 0 do
    parent_ap_id =
      object.data
      |> Map.get("inReplyTo")
      |> in_reply_to_ap_id()

    cond do
      not is_binary(parent_ap_id) ->
        []

      MapSet.member?(visited, parent_ap_id) ->
        []

      true ->
        case get_by_ap_id(parent_ap_id) do
          %Object{} = parent ->
            [parent | do_thread_ancestors(parent, MapSet.put(visited, parent_ap_id), limit - 1)]

          _ ->
            []
        end
    end
  end

  defp do_thread_ancestors(_object, _visited, _limit), do: []

  def thread_descendants(object, limit \\ 50)

  def thread_descendants(%Object{} = object, limit) when is_integer(limit) and limit > 0 do
    {acc, _visited, _remaining} =
      do_thread_descendants(object.ap_id, MapSet.new([object.ap_id]), limit, [])

    Enum.reverse(acc)
  end

  def thread_descendants(_object, _limit), do: []

  defp do_thread_descendants(ap_id, visited, remaining, acc)
       when is_binary(ap_id) and is_integer(remaining) and remaining > 0 and is_list(acc) do
    replies = list_replies_to(ap_id, limit: remaining)

    Enum.reduce_while(replies, {acc, visited, remaining}, fn reply, {acc, visited, remaining} ->
      if remaining <= 0 do
        {:halt, {acc, visited, remaining}}
      else
        if MapSet.member?(visited, reply.ap_id) do
          {:cont, {acc, visited, remaining}}
        else
          visited = MapSet.put(visited, reply.ap_id)
          remaining = remaining - 1
          acc = [reply | acc]

          {acc, visited, remaining} =
            do_thread_descendants(reply.ap_id, visited, remaining, acc)

          {:cont, {acc, visited, remaining}}
        end
      end
    end)
  end

  defp do_thread_descendants(_ap_id, visited, remaining, acc), do: {acc, visited, remaining}

  def list_replies_to(object_ap_id, opts \\ [])
      when is_binary(object_ap_id) and is_list(opts) do
    limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()

    from(o in Object,
      where:
        o.type == "Note" and
          fragment("?->>'inReplyTo' = ?", o.data, ^object_ap_id),
      order_by: [asc: o.id],
      limit: ^limit
    )
    |> Repo.all()
  end

  defp in_reply_to_ap_id(value) when is_binary(value), do: value
  defp in_reply_to_ap_id(%{"id" => id}) when is_binary(id), do: id
  defp in_reply_to_ap_id(_), do: nil

  def list_creates_by_actor(actor, limit \\ 20) when is_binary(actor) do
    from(o in Object,
      where: o.type == "Create" and o.actor == ^actor,
      order_by: [desc: o.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  def count_creates_by_actor(actor) when is_binary(actor) do
    from(o in Object, where: o.type == "Create" and o.actor == ^actor)
    |> Repo.aggregate(:count, :id)
  end

  def delete_all_notes do
    from(o in Object, where: o.type == "Note")
    |> Repo.delete_all()
  end

  defp maybe_where_max_id(query, max_id) when is_integer(max_id) and max_id > 0 do
    from(o in query, where: o.id < ^max_id)
  end

  defp maybe_where_max_id(query, _max_id), do: query

  defp maybe_where_since_id(query, since_id) when is_integer(since_id) and since_id > 0 do
    from(o in query, where: o.id > ^since_id)
  end

  defp maybe_where_since_id(query, _since_id), do: query

  defp normalize_limit(limit) when is_integer(limit) do
    limit
    |> max(1)
    |> min(40)
  end

  defp normalize_limit(_), do: 20

  defp unique_ap_id_error?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:ap_id, {_msg, opts}} -> Keyword.get(opts, :constraint) == :unique
      _ -> false
    end)
  end
end
