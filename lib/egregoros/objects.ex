defmodule Egregoros.Objects do
  import Ecto.Query, only: [from: 2, dynamic: 2]

  alias Egregoros.Object
  alias Egregoros.Relationship
  alias Egregoros.Relationships
  alias Egregoros.Repo

  @as_public "https://www.w3.org/ns/activitystreams#Public"
  @recipient_fields ~w(to cc bto bcc audience)

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
    upsert_object(attrs, conflict: :nothing)
  end

  def upsert_object(attrs, opts) when is_list(opts) do
    conflict = Keyword.get(opts, :conflict, :nothing)

    case create_object(attrs) do
      {:ok, %Object{} = object} ->
        {:ok, object}

      {:error, %Ecto.Changeset{} = changeset} ->
        if unique_ap_id_error?(changeset) do
          ap_id = Map.get(attrs, :ap_id) || Map.get(attrs, "ap_id")

          case get_by_ap_id(ap_id) do
            %Object{} = object -> resolve_conflict(conflict, object, attrs, changeset)
            _ -> {:error, changeset}
          end
        else
          {:error, changeset}
        end
    end
  end

  def upsert_object(attrs, _opts), do: upsert_object(attrs)

  def get_by_ap_id(nil), do: nil
  def get_by_ap_id(ap_id) when is_binary(ap_id), do: Repo.get_by(Object, ap_id: ap_id)

  def list_by_ap_ids(ap_ids) when is_list(ap_ids) do
    ap_ids =
      ap_ids
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    if ap_ids == [] do
      []
    else
      from(o in Object, where: o.ap_id in ^ap_ids)
      |> Repo.all()
    end
  end

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

  def list_public_notes, do: list_public_notes(limit: 20)

  def list_public_notes(limit) when is_integer(limit) do
    list_public_notes(limit: limit)
  end

  def list_public_notes(opts) when is_list(opts) do
    limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()
    max_id = Keyword.get(opts, :max_id)
    since_id = Keyword.get(opts, :since_id)

    from(o in Object,
      where: o.type == "Note",
      order_by: [desc: o.id],
      limit: ^limit
    )
    |> where_publicly_listed()
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
      |> String.downcase()

    if tag == "" do
      []
    else
      limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()
      max_id = Keyword.get(opts, :max_id)
      since_id = Keyword.get(opts, :since_id)
      tag_name = "#" <> tag

      from(o in Object,
        where: o.type == "Note",
        order_by: [desc: o.id],
        limit: ^limit
      )
      |> where_publicly_visible()
      |> where_hashtag_tag(tag_name)
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
      |> where_publicly_visible()
      |> Repo.all()
    end
  end

  def search_notes(_query, _opts), do: []

  @status_types ~w(Note Announce)

  defp where_announces_have_object(query) do
    from(o in query,
      left_join: reblog in Object,
      on: reblog.ap_id == o.object,
      where: o.type != "Announce" or not is_nil(reblog.id)
    )
  end

  def list_public_statuses(opts \\ []) when is_list(opts) do
    limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()
    max_id = Keyword.get(opts, :max_id)
    since_id = Keyword.get(opts, :since_id)
    local_only? = Keyword.get(opts, :local, false) == true
    remote_only? = Keyword.get(opts, :remote, false) == true
    only_media? = Keyword.get(opts, :only_media, false) == true

    from(o in Object,
      where: o.type in ^@status_types,
      order_by: [desc: o.id],
      limit: ^limit
    )
    |> where_announces_have_object()
    |> where_publicly_listed()
    |> maybe_where_origin(local_only?, remote_only?)
    |> maybe_where_only_media(only_media?)
    |> maybe_where_max_id(max_id)
    |> maybe_where_since_id(since_id)
    |> Repo.all()
  end

  def list_public_statuses_by_hashtag(tag, opts \\ [])

  def list_public_statuses_by_hashtag(tag, opts) when is_binary(tag) and is_list(opts) do
    tag =
      tag
      |> String.trim()
      |> String.trim_leading("#")
      |> String.downcase()

    if tag == "" do
      []
    else
      limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()
      max_id = Keyword.get(opts, :max_id)
      since_id = Keyword.get(opts, :since_id)
      local_only? = Keyword.get(opts, :local, false) == true
      remote_only? = Keyword.get(opts, :remote, false) == true
      only_media? = Keyword.get(opts, :only_media, false) == true
      tag_name = "#" <> tag

      from(o in Object,
        where: o.type in ^@status_types,
        order_by: [desc: o.id],
        limit: ^limit
      )
      |> where_announces_have_object()
      |> where_publicly_listed()
      |> where_hashtag_tag_with_reblog(tag_name)
      |> maybe_where_origin(local_only?, remote_only?)
      |> maybe_where_only_media_with_reblog(only_media?)
      |> maybe_where_max_id(max_id)
      |> maybe_where_since_id(since_id)
      |> Repo.all()
    end
  end

  def list_public_statuses_by_hashtag(_tag, _opts), do: []

  def publicly_visible?(%Object{data: %{} = data}) do
    to = data |> Map.get("to", []) |> List.wrap()
    cc = data |> Map.get("cc", []) |> List.wrap()
    audience = data |> Map.get("audience", []) |> List.wrap()
    @as_public in to or @as_public in cc or @as_public in audience
  end

  def publicly_visible?(_object), do: false

  def publicly_listed?(%Object{data: %{} = data}) do
    to = data |> Map.get("to", []) |> List.wrap()
    @as_public in to
  end

  def publicly_listed?(_object), do: false

  def visible_to?(%Object{} = object, nil), do: publicly_visible?(object)

  def visible_to?(%Object{} = object, %Egregoros.User{ap_id: ap_id})
      when is_binary(ap_id) do
    visible_to?(object, ap_id)
  end

  def visible_to?(%Object{} = object, user_ap_id) when is_binary(user_ap_id) do
    cond do
      object.actor == user_ap_id -> true
      publicly_visible?(object) -> true
      recipient?(object, user_ap_id) -> true
      followers_visible?(object, user_ap_id) -> true
      true -> false
    end
  end

  defp where_publicly_visible(query) do
    from(o in query,
      where:
        fragment("? @> ?", o.data, ^%{"to" => [@as_public]}) or
          fragment("? @> ?", o.data, ^%{"cc" => [@as_public]}) or
          fragment("? @> ?", o.data, ^%{"audience" => [@as_public]})
    )
  end

  defp where_publicly_listed(query) do
    from(o in query,
      where: fragment("? @> ?", o.data, ^%{"to" => [@as_public]})
    )
  end

  defp maybe_where_origin(query, true, _remote_only?) do
    from(o in query, where: o.local == true)
  end

  defp maybe_where_origin(query, false, true) do
    from(o in query, where: o.local == false)
  end

  defp maybe_where_origin(query, _local_only?, _remote_only?), do: query

  defp maybe_where_only_media(query, true) do
    from(o in query,
      where:
        fragment(
          "jsonb_typeof(?->'attachment') = 'array' AND jsonb_array_length(?->'attachment') > 0",
          o.data,
          o.data
        )
    )
  end

  defp maybe_where_only_media(query, _only_media?), do: query

  defp maybe_where_only_media_with_reblog(query, true) do
    from([o, reblog] in query,
      where:
        (o.type == "Note" and
           fragment(
             "jsonb_typeof(?->'attachment') = 'array' AND jsonb_array_length(?->'attachment') > 0",
             o.data,
             o.data
           )) or
          (o.type == "Announce" and
             fragment(
               "jsonb_typeof(?->'attachment') = 'array' AND jsonb_array_length(?->'attachment') > 0",
               reblog.data,
               reblog.data
             ))
    )
  end

  defp maybe_where_only_media_with_reblog(query, _only_media?), do: query

  defp recipient?(%Object{data: %{} = data}, recipient) when is_binary(recipient) do
    recipient = String.trim(recipient)

    if recipient == "" do
      false
    else
      Enum.any?(@recipient_fields, fn field ->
        data
        |> Map.get(field)
        |> List.wrap()
        |> Enum.any?(fn
          %{"id" => id} when is_binary(id) -> String.trim(id) == recipient
          %{id: id} when is_binary(id) -> String.trim(id) == recipient
          id when is_binary(id) -> String.trim(id) == recipient
          _ -> false
        end)
      end)
    end
  end

  defp recipient?(_object, _recipient), do: false

  defp followers_visible?(%Object{actor: actor, data: %{} = data}, user_ap_id)
       when is_binary(actor) and is_binary(user_ap_id) do
    followers = actor <> "/followers"
    to = data |> Map.get("to", []) |> List.wrap()
    cc = data |> Map.get("cc", []) |> List.wrap()

    if followers in to or followers in cc do
      Relationships.get_by_type_actor_object("Follow", user_ap_id, actor) != nil
    else
      false
    end
  end

  defp followers_visible?(_object, _user_ap_id), do: false

  defp where_hashtag_tag(query, name) when is_binary(name) and name != "" do
    match = [%{"type" => "Hashtag", "name" => name}]

    from(o in query,
      where: fragment("coalesce(?->'tag', '[]'::jsonb) @> ?", o.data, ^match)
    )
  end

  defp where_hashtag_tag(query, _name), do: query

  defp where_hashtag_tag_with_reblog(query, name) when is_binary(name) and name != "" do
    match = [%{"type" => "Hashtag", "name" => name}]

    from([o, reblog] in query,
      where:
        (o.type == "Note" and fragment("coalesce(?->'tag', '[]'::jsonb) @> ?", o.data, ^match)) or
          (o.type == "Announce" and
             fragment("coalesce(?->'tag', '[]'::jsonb) @> ?", reblog.data, ^match))
    )
  end

  defp where_hashtag_tag_with_reblog(query, _name), do: query

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

    ignored_actor_subquery =
      from(r in Relationship,
        where: r.actor == ^actor_ap_id and r.type in ["Block", "Mute"],
        select: r.object
      )

    followed_subquery =
      from(r in Relationship,
        where: r.type == "Follow" and r.actor == ^actor_ap_id,
        select: r.object
      )

    from(o in Object,
      where:
        o.type == "Note" and
          o.actor not in subquery(ignored_actor_subquery) and
          (o.actor == ^actor_ap_id or
             o.actor in subquery(followed_subquery) or
             fragment("? @> ?", o.data, ^%{"to" => [actor_ap_id]}) or
             fragment("? @> ?", o.data, ^%{"cc" => [actor_ap_id]}) or
             fragment("? @> ?", o.data, ^%{"bto" => [actor_ap_id]}) or
             fragment("? @> ?", o.data, ^%{"bcc" => [actor_ap_id]}) or
             fragment("? @> ?", o.data, ^%{"audience" => [actor_ap_id]})),
      order_by: [desc: o.id],
      limit: ^limit
    )
    |> where_visible_to_home(actor_ap_id)
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

    ignored_actor_subquery =
      from(r in Relationship,
        where: r.actor == ^actor_ap_id and r.type in ["Block", "Mute"],
        select: r.object
      )

    followed_subquery =
      from(r in Relationship,
        where: r.type == "Follow" and r.actor == ^actor_ap_id,
        select: r.object
      )

    from(o in Object,
      where:
        o.type in ^@status_types and
          o.actor not in subquery(ignored_actor_subquery) and
          (o.actor == ^actor_ap_id or
             o.actor in subquery(followed_subquery) or
             fragment("? @> ?", o.data, ^%{"to" => [actor_ap_id]}) or
             fragment("? @> ?", o.data, ^%{"cc" => [actor_ap_id]}) or
             fragment("? @> ?", o.data, ^%{"bto" => [actor_ap_id]}) or
             fragment("? @> ?", o.data, ^%{"bcc" => [actor_ap_id]}) or
             fragment("? @> ?", o.data, ^%{"audience" => [actor_ap_id]})),
      order_by: [desc: o.id],
      limit: ^limit
    )
    |> where_announces_have_object()
    |> where_visible_to_home(actor_ap_id)
    |> maybe_where_max_id(max_id)
    |> maybe_where_since_id(since_id)
    |> Repo.all()
  end

  defp where_visible_to_home(query, user_ap_id) when is_binary(user_ap_id) do
    base =
      dynamic(
        [o],
        o.actor == ^user_ap_id or
          fragment("? @> ?", o.data, ^%{"to" => [@as_public]}) or
          fragment("? @> ?", o.data, ^%{"cc" => [@as_public]}) or
          fragment("? @> ?", o.data, ^%{"audience" => [@as_public]}) or
          fragment("? @> ?", o.data, ^%{"to" => [user_ap_id]}) or
          fragment("? @> ?", o.data, ^%{"cc" => [user_ap_id]}) or
          fragment("? @> ?", o.data, ^%{"bto" => [user_ap_id]}) or
          fragment("? @> ?", o.data, ^%{"bcc" => [user_ap_id]}) or
          fragment("? @> ?", o.data, ^%{"audience" => [user_ap_id]})
      )

    visibility_dynamic =
      dynamic(
        [o],
        ^base or
          fragment("jsonb_exists((?->'to'), (? || '/followers'))", o.data, o.actor) or
          fragment("jsonb_exists((?->'cc'), (? || '/followers'))", o.data, o.actor)
      )

    from(o in query, where: ^visibility_dynamic)
  end

  defp where_visible_on_profile(query, actor_ap_id, nil)
       when is_binary(actor_ap_id) do
    where_publicly_visible(query)
  end

  defp where_visible_on_profile(query, actor_ap_id, viewer_ap_id)
       when is_binary(actor_ap_id) and is_binary(viewer_ap_id) do
    cond do
      actor_ap_id == viewer_ap_id ->
        query

      Relationships.get_by_type_actor_object("Follow", viewer_ap_id, actor_ap_id) != nil ->
        followers_collection = actor_ap_id <> "/followers"

        from(o in query,
          where:
            fragment("? @> ?", o.data, ^%{"to" => [@as_public]}) or
              fragment("? @> ?", o.data, ^%{"cc" => [@as_public]}) or
              fragment("? @> ?", o.data, ^%{"to" => [followers_collection]}) or
              fragment("? @> ?", o.data, ^%{"cc" => [followers_collection]})
        )

      true ->
        where_publicly_visible(query)
    end
  end

  defp where_visible_on_profile(query, _actor_ap_id, _viewer_ap_id), do: query

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

  def list_visible_notes_by_actor(actor, viewer, opts \\ [])

  def list_visible_notes_by_actor(actor, viewer, opts) when is_binary(actor) and is_list(opts) do
    limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()
    max_id = Keyword.get(opts, :max_id)
    since_id = Keyword.get(opts, :since_id)

    viewer_ap_id =
      case viewer do
        %Egregoros.User{ap_id: ap_id} when is_binary(ap_id) -> ap_id
        ap_id when is_binary(ap_id) -> ap_id
        _ -> nil
      end

    from(o in Object,
      where: o.type == "Note" and o.actor == ^actor,
      order_by: [desc: o.id],
      limit: ^limit
    )
    |> where_visible_on_profile(actor, viewer_ap_id)
    |> maybe_where_max_id(max_id)
    |> maybe_where_since_id(since_id)
    |> Repo.all()
  end

  def list_visible_notes_by_actor(_actor, _viewer, _opts), do: []

  def list_visible_statuses_by_actor(actor, viewer, opts \\ [])

  def list_visible_statuses_by_actor(actor, viewer, opts) when is_binary(actor) and is_list(opts) do
    limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()
    max_id = Keyword.get(opts, :max_id)
    since_id = Keyword.get(opts, :since_id)

    viewer_ap_id =
      case viewer do
        %Egregoros.User{ap_id: ap_id} when is_binary(ap_id) -> ap_id
        ap_id when is_binary(ap_id) -> ap_id
        _ -> nil
      end

    from(o in Object,
      where: o.type in ^@status_types and o.actor == ^actor,
      order_by: [desc: o.id],
      limit: ^limit
    )
    |> where_announces_have_object()
    |> where_visible_on_profile(actor, viewer_ap_id)
    |> maybe_where_max_id(max_id)
    |> maybe_where_since_id(since_id)
    |> Repo.all()
  end

  def list_visible_statuses_by_actor(_actor, _viewer, _opts), do: []

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
    |> where_announces_have_object()
    |> maybe_where_max_id(max_id)
    |> maybe_where_since_id(since_id)
    |> Repo.all()
  end

  def list_public_statuses_by_actor(actor) when is_binary(actor),
    do: list_public_statuses_by_actor(actor, limit: 20)

  def list_public_statuses_by_actor(actor, opts) when is_binary(actor) and is_list(opts) do
    limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()
    max_id = Keyword.get(opts, :max_id)
    since_id = Keyword.get(opts, :since_id)

    from(o in Object,
      where: o.type in ^@status_types and o.actor == ^actor,
      order_by: [desc: o.id],
      limit: ^limit
    )
    |> where_announces_have_object()
    |> where_publicly_visible()
    |> maybe_where_max_id(max_id)
    |> maybe_where_since_id(since_id)
    |> Repo.all()
  end

  def count_notes_by_actor(actor) when is_binary(actor) do
    from(o in Object, where: o.type == "Note" and o.actor == ^actor)
    |> Repo.aggregate(:count, :id)
  end

  def count_notes_by_actors(actor_ap_ids) when is_list(actor_ap_ids) do
    actor_ap_ids =
      actor_ap_ids
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    if actor_ap_ids == [] do
      %{}
    else
      from(o in Object,
        where: o.type == "Note" and o.actor in ^actor_ap_ids,
        group_by: o.actor,
        select: {o.actor, count(o.id)}
      )
      |> Repo.all()
      |> Map.new()
    end
  end

  def count_note_replies_by_parent_ap_ids(parent_ap_ids) when is_list(parent_ap_ids) do
    parent_ap_ids =
      parent_ap_ids
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    if parent_ap_ids == [] do
      %{}
    else
      from(o in Object,
        where: o.type == "Note",
        where:
          fragment(
            "coalesce(?->>'inReplyTo', ?->'inReplyTo'->>'id')",
            o.data,
            o.data
          ) in ^parent_ap_ids,
        group_by:
          fragment(
            "coalesce(?->>'inReplyTo', ?->'inReplyTo'->>'id')",
            o.data,
            o.data
          ),
        select:
          {fragment("coalesce(?->>'inReplyTo', ?->'inReplyTo'->>'id')", o.data, o.data),
           count(o.id)}
      )
      |> Repo.all()
      |> Map.new()
    end
  end

  def count_visible_notes_by_actor(actor, viewer) when is_binary(actor) do
    viewer_ap_id =
      case viewer do
        %Egregoros.User{ap_id: ap_id} when is_binary(ap_id) -> ap_id
        ap_id when is_binary(ap_id) -> ap_id
        _ -> nil
      end

    from(o in Object, where: o.type == "Note" and o.actor == ^actor)
    |> where_visible_on_profile(actor, viewer_ap_id)
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

  def list_public_creates_by_actor(actor, limit \\ 20) when is_binary(actor) do
    from(o in Object,
      where: o.type == "Create" and o.actor == ^actor,
      order_by: [desc: o.inserted_at],
      limit: ^limit
    )
    |> where_publicly_visible()
    |> Repo.all()
  end

  def count_creates_by_actor(actor) when is_binary(actor) do
    from(o in Object, where: o.type == "Create" and o.actor == ^actor)
    |> Repo.aggregate(:count, :id)
  end

  def count_public_creates_by_actor(actor) when is_binary(actor) do
    from(o in Object, where: o.type == "Create" and o.actor == ^actor)
    |> where_publicly_visible()
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

  defp resolve_conflict(:nothing, %Object{} = object, _attrs, _changeset), do: {:ok, object}

  defp resolve_conflict(:replace, %Object{} = object, attrs, changeset) when is_map(attrs) do
    cond do
      ap_id_mismatch?(object, attrs) ->
        {:error, changeset}

      type_mismatch?(object, attrs) ->
        {:error, changeset}

      true ->
        attrs =
          attrs
          |> Map.delete(:ap_id)
          |> Map.delete("ap_id")
          |> Map.delete(:type)
          |> Map.delete("type")

        update_object(object, attrs)
    end
  end

  defp resolve_conflict(_other, %Object{} = object, _attrs, _changeset), do: {:ok, object}

  defp ap_id_mismatch?(%Object{ap_id: existing}, attrs) when is_map(attrs) and is_binary(existing) do
    case Map.get(attrs, :ap_id) || Map.get(attrs, "ap_id") do
      nil -> false
      value when is_binary(value) -> String.trim(value) != "" and String.trim(value) != existing
      _ -> true
    end
  end

  defp ap_id_mismatch?(_object, _attrs), do: false

  defp type_mismatch?(%Object{type: existing}, attrs) when is_map(attrs) and is_binary(existing) do
    case Map.get(attrs, :type) || Map.get(attrs, "type") do
      nil -> false
      value when is_binary(value) -> String.trim(value) != "" and String.trim(value) != existing
      _ -> true
    end
  end

  defp type_mismatch?(_object, _attrs), do: false

  defp unique_ap_id_error?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:ap_id, {_msg, opts}} -> Keyword.get(opts, :constraint) == :unique
      _ -> false
    end)
  end
end
