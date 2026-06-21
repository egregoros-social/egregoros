defmodule Egregoros.Objects do
  import Ecto.Query,
    only: [from: 2, dynamic: 2, recursive_ctes: 2, with_cte: 3, subquery: 1]

  alias Egregoros.ActivityPub.TypeNormalizer
  alias Egregoros.Object
  alias Egregoros.Objects.Polls
  alias Egregoros.Relationship
  alias Egregoros.Relationships
  alias Egregoros.Repo
  alias Egregoros.Users

  @as_public "https://www.w3.org/ns/activitystreams#Public"
  @recipient_fields ~w(to cc bto bcc audience)

  # Delegations to submodules
  defdelegate increase_vote_count(question_ap_id, option_name, voter_ap_id), to: Polls
  defdelegate poll_is_multiple?(object), to: Polls, as: :multiple?

  def create_object(attrs) do
    # Apply multi-type metadata before persistence so the canonical type array
    # stays in data and auxiliary types live in internal state.
    attrs = TypeNormalizer.apply_type_metadata(attrs)

    %Object{}
    |> Object.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, %Object{} = object} ->
        _ = maybe_bump_actor_last_activity(object)
        {:ok, object}

      other ->
        other
    end
  end

  def update_object(%Object{} = object, attrs) do
    # Apply multi-type metadata on updates as well to preserve canonical data.
    attrs = TypeNormalizer.apply_type_metadata(attrs)

    object
    |> Object.changeset(attrs)
    |> Repo.update()
  end

  defp maybe_bump_actor_last_activity(%Object{actor: actor, inserted_at: inserted_at})
       when is_binary(actor) and actor != "" and not is_nil(inserted_at) do
    Users.bump_last_activity_at(actor, inserted_at)
  end

  defp maybe_bump_actor_last_activity(_object), do: :ok

  def upsert_object(attrs) do
    upsert_object(attrs, conflict: :nothing)
  end

  def upsert_object(attrs, opts) when is_list(opts) do
    # Normalize multi-type metadata once up front so both inserts and conflict
    # resolutions see canonical data and auxiliary types.
    attrs = TypeNormalizer.apply_type_metadata(attrs)
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

  def get(id) when is_binary(id) do
    id = String.trim(id)

    cond do
      id == "" ->
        nil

      true ->
        if flake_id?(id) do
          Repo.get(Object, id)
        else
          nil
        end
    end
  end

  def get(_id), do: nil

  def get_by_type_actor_object(type, actor, object)
      when is_binary(type) and is_binary(actor) and is_binary(object) do
    from(o in Object,
      where: o.type == ^type and o.actor == ^actor and o.object == ^object,
      order_by: [desc: o.inserted_at, desc: o.id],
      limit: 1
    )
    |> Repo.one()
  end

  def list_by_type_actor(type, actor_ap_id, opts \\ [])

  def list_by_type_actor(type, actor_ap_id, opts)
      when is_binary(type) and is_binary(actor_ap_id) and is_list(opts) do
    limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()
    max_id = Keyword.get(opts, :max_id)

    from(o in Object,
      where: o.type == ^type and o.actor == ^actor_ap_id,
      order_by: [desc: o.id],
      limit: ^limit
    )
    |> maybe_where_max_id(max_id)
    |> Repo.all()
  end

  def list_by_type_actor(_type, _actor_ap_id, _opts), do: []

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
    local_only? = Keyword.get(opts, :local, false) == true
    remote_only? = Keyword.get(opts, :remote, false) == true

    from(o in Object,
      where: o.type == "Note",
      order_by: [desc: o.id],
      limit: ^limit
    )
    |> where_publicly_listed()
    |> maybe_where_origin(local_only?, remote_only?)
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

      :telemetry.span(
        [:egregoros, :timeline, :read],
        %{name: :list_notes_by_hashtag, limit: limit},
        fn ->
          query =
            from(o in Object,
              where: o.type == "Note",
              order_by: [desc: o.id],
              limit: ^limit
            )
            |> where_publicly_visible()
            |> where_hashtag_tag(tag_name)
            |> maybe_where_max_id(max_id)
            |> maybe_where_since_id(since_id)

          objects =
            Repo.all(query,
              telemetry_options: [feature: :timeline, name: :list_notes_by_hashtag]
            )

          {objects, %{count: length(objects), name: :list_notes_by_hashtag}}
        end
      )
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

  def search_visible_notes(query, viewer, opts \\ [])

  def search_visible_notes(query, viewer, opts) when is_binary(query) and is_list(opts) do
    query = String.trim(query)
    limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()

    viewer_ap_id =
      case viewer do
        %Egregoros.User{ap_id: ap_id} when is_binary(ap_id) and ap_id != "" -> ap_id
        ap_id when is_binary(ap_id) and ap_id != "" -> ap_id
        _ -> nil
      end

    if query == "" do
      []
    else
      pattern = "%" <> query <> "%"

      search_query =
        from(o in Object,
          where:
            o.type == "Note" and
              (fragment("?->>'content' ILIKE ?", o.data, ^pattern) or
                 fragment("?->>'summary' ILIKE ?", o.data, ^pattern)),
          order_by: [desc: o.id],
          limit: ^limit
        )

      if is_binary(viewer_ap_id) do
        base_visibility =
          dynamic(
            [o, follow],
            o.actor == ^viewer_ap_id or
              fragment("? @> ?", o.data, ^%{"to" => [@as_public]}) or
              fragment("? @> ?", o.data, ^%{"cc" => [@as_public]}) or
              fragment("? @> ?", o.data, ^%{"audience" => [@as_public]}) or
              fragment("? @> ?", o.data, ^%{"to" => [viewer_ap_id]}) or
              fragment("? @> ?", o.data, ^%{"cc" => [viewer_ap_id]}) or
              fragment("? @> ?", o.data, ^%{"bto" => [viewer_ap_id]}) or
              fragment("? @> ?", o.data, ^%{"bcc" => [viewer_ap_id]}) or
              fragment("? @> ?", o.data, ^%{"audience" => [viewer_ap_id]})
          )

        followers_visibility =
          dynamic(
            [o, follow],
            not is_nil(follow.id) and
              (fragment("jsonb_exists((?->'to'), (? || '/followers'))", o.data, o.actor) or
                 fragment("jsonb_exists((?->'cc'), (? || '/followers'))", o.data, o.actor))
          )

        from(o in search_query,
          left_join: follow in Relationship,
          on:
            follow.type == "Follow" and follow.actor == ^viewer_ap_id and follow.object == o.actor,
          where: ^dynamic([o, follow], ^base_visibility or ^followers_visibility)
        )
        |> Repo.all()
      else
        search_query
        |> where_publicly_visible()
        |> Repo.all()
      end
    end
  end

  def search_visible_notes(_query, _viewer, _opts), do: []

  @status_types ~w(Note Announce Question)

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

    :telemetry.span(
      [:egregoros, :timeline, :read],
      %{
        name: :list_public_statuses,
        local_only?: local_only?,
        remote_only?: remote_only?,
        only_media?: only_media?,
        limit: limit
      },
      fn ->
        query =
          from(o in Object,
            where: o.type in ^@status_types,
            order_by: [desc: o.id],
            limit: ^limit
          )
          |> where_announces_have_object()
          |> where_publicly_listed()
          |> maybe_where_origin(local_only?, remote_only?)
          |> maybe_where_only_media_with_reblog(only_media?)
          |> maybe_where_max_id(max_id)
          |> maybe_where_since_id(since_id)

        objects =
          Repo.all(query,
            telemetry_options: [feature: :timeline, name: :list_public_statuses]
          )

        {objects, %{count: length(objects), name: :list_public_statuses}}
      end
    )
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

      :telemetry.span(
        [:egregoros, :timeline, :read],
        %{
          name: :list_public_statuses_by_hashtag,
          local_only?: local_only?,
          remote_only?: remote_only?,
          only_media?: only_media?,
          limit: limit
        },
        fn ->
          query =
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

          objects =
            Repo.all(query,
              telemetry_options: [feature: :timeline, name: :list_public_statuses_by_hashtag]
            )

          {objects, %{count: length(objects), name: :list_public_statuses_by_hashtag}}
        end
      )
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

  defp maybe_where_only_media_with_reblog(query, true) do
    from([o, reblog] in query,
      where:
        (o.type == "Note" and o.has_media == true) or
          (o.type == "Announce" and reblog.has_media == true)
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
    match = %{"tag" => [%{"type" => "Hashtag", "name" => name}]}

    from(o in query,
      where: fragment("? @> ?", o.data, ^match)
    )
  end

  defp where_hashtag_tag(query, _name), do: query

  defp where_hashtag_tag_with_reblog(query, name) when is_binary(name) and name != "" do
    match = %{"tag" => [%{"type" => "Hashtag", "name" => name}]}

    from([o, reblog] in query,
      where:
        (o.type == "Note" and fragment("? @> ?", o.data, ^match)) or
          (o.type == "Announce" and
             fragment("? @> ?", reblog.data, ^match))
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

    base_query =
      from(o in Object,
        where: o.type == "Note" and o.actor not in subquery(ignored_actor_subquery)
      )

    actor_query =
      from(o in base_query,
        where: o.actor == ^actor_ap_id or o.actor in subquery(followed_subquery)
      )
      |> where_visible_to_home(actor_ap_id)

    addressed_query =
      from(o in base_query,
        where:
          o.actor != ^actor_ap_id and
            o.actor not in subquery(followed_subquery) and
            (fragment("? @> ?", o.data, ^%{"to" => [actor_ap_id]}) or
               fragment("? @> ?", o.data, ^%{"cc" => [actor_ap_id]}) or
               fragment("? @> ?", o.data, ^%{"bto" => [actor_ap_id]}) or
               fragment("? @> ?", o.data, ^%{"bcc" => [actor_ap_id]}) or
               fragment("? @> ?", o.data, ^%{"audience" => [actor_ap_id]}))
      )

    actor_query =
      actor_query
      |> maybe_where_max_id(max_id)
      |> maybe_where_since_id(since_id)

    addressed_query =
      addressed_query
      |> maybe_where_max_id(max_id)
      |> maybe_where_since_id(since_id)

    actor_ids = from(o in actor_query, select: %{id: o.id})
    addressed_ids = from(o in addressed_query, select: %{id: o.id})

    ids_query = Ecto.Query.union_all(actor_ids, ^addressed_ids)

    from(o in Object,
      join: ids in subquery(ids_query),
      on: o.id == ids.id,
      order_by: [desc: o.id],
      limit: ^limit
    )
    |> Repo.all()
  end

  def list_home_statuses(actor_ap_id) when is_binary(actor_ap_id) do
    list_home_statuses(actor_ap_id, limit: 20)
  end

  def list_home_statuses(actor_ap_id, opts) when is_binary(actor_ap_id) and is_list(opts) do
    limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()
    max_id = Keyword.get(opts, :max_id)
    since_id = Keyword.get(opts, :since_id)

    :telemetry.span(
      [:egregoros, :timeline, :read],
      %{name: :list_home_statuses, limit: limit},
      fn ->
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

        base_query =
          from(o in Object,
            where: o.type in ^@status_types and o.actor not in subquery(ignored_actor_subquery)
          )
          |> where_announces_have_object()

        actor_query =
          from([o, _reblog] in base_query,
            where: o.actor == ^actor_ap_id or o.actor in subquery(followed_subquery)
          )
          |> where_visible_to_home(actor_ap_id)

        addressed_query =
          from([o, _reblog] in base_query,
            where:
              o.actor != ^actor_ap_id and
                o.actor not in subquery(followed_subquery) and
                (fragment("? @> ?", o.data, ^%{"to" => [actor_ap_id]}) or
                   fragment("? @> ?", o.data, ^%{"cc" => [actor_ap_id]}) or
                   fragment("? @> ?", o.data, ^%{"bto" => [actor_ap_id]}) or
                   fragment("? @> ?", o.data, ^%{"bcc" => [actor_ap_id]}) or
                   fragment("? @> ?", o.data, ^%{"audience" => [actor_ap_id]}))
          )

        actor_query =
          actor_query
          |> maybe_where_max_id(max_id)
          |> maybe_where_since_id(since_id)

        addressed_query =
          addressed_query
          |> maybe_where_max_id(max_id)
          |> maybe_where_since_id(since_id)

        actor_ids = from([o, _reblog] in actor_query, select: %{id: o.id})
        addressed_ids = from([o, _reblog] in addressed_query, select: %{id: o.id})

        ids_query = Ecto.Query.union_all(actor_ids, ^addressed_ids)

        query =
          from(o in Object,
            join: ids in subquery(ids_query),
            on: o.id == ids.id,
            order_by: [desc: o.id],
            limit: ^limit
          )

        objects =
          Repo.all(query,
            telemetry_options: [feature: :timeline, name: :list_home_statuses]
          )

        {objects, %{count: length(objects), name: :list_home_statuses}}
      end
    )
  end

  @for_you_neighbor_limit 50
  @for_you_like_scan_limit 500

  def list_for_you_statuses(actor_ap_id, opts \\ [])

  def list_for_you_statuses(actor_ap_id, opts)
      when is_binary(actor_ap_id) and is_list(opts) do
    actor_ap_id = String.trim(actor_ap_id)

    if actor_ap_id == "" do
      []
    else
      limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()
      max_like_id = Keyword.get(opts, :max_id)
      since_like_id = Keyword.get(opts, :since_id)

      :telemetry.span(
        [:egregoros, :timeline, :read],
        %{name: :list_for_you_statuses, limit: limit},
        fn ->
          ignored_actor_subquery =
            from(r in Relationship,
              where: r.actor == ^actor_ap_id and r.type in ["Block", "Mute"],
              select: r.object
            )

          viewer_liked_objects =
            from(l in Object,
              where:
                l.type == "Like" and l.actor == ^actor_ap_id and not is_nil(l.object) and
                  l.object != "",
              distinct: l.object,
              select: l.object
            )

          similar_actors =
            from(l in Object,
              where:
                l.type == "Like" and l.object in subquery(viewer_liked_objects) and
                  l.actor != ^actor_ap_id,
              group_by: l.actor,
              order_by: [desc: count(l.id)],
              select: l.actor,
              limit: ^@for_you_neighbor_limit
            )

          latest_like_by_object =
            from(l in Object,
              where:
                l.type == "Like" and l.actor in subquery(similar_actors) and
                  l.object not in subquery(viewer_liked_objects) and not is_nil(l.object) and
                  l.object != "",
              distinct: l.object,
              order_by: [asc: l.object, desc: l.id],
              select: %{object_ap_id: l.object, like_id: l.id}
            )

          latest_like_ids_by_object =
            from(lr in subquery(latest_like_by_object),
              order_by: [desc: lr.like_id],
              limit: ^@for_you_like_scan_limit
            )

          like_rows =
            from(l in Object,
              join: latest in subquery(latest_like_ids_by_object),
              on: l.id == latest.like_id,
              select: %{object_ap_id: latest.object_ap_id, like_id: l.id}
            )

          query =
            from(o in Object,
              join: lr in subquery(like_rows),
              on: o.ap_id == lr.object_ap_id,
              where: o.type in ^@status_types,
              where: o.actor not in subquery(ignored_actor_subquery),
              order_by: [desc: lr.like_id],
              limit: ^limit,
              select: {o, lr.like_id}
            )
            |> where_announces_have_object()
            |> where_publicly_visible()
            |> maybe_where_for_you_max_like_id(max_like_id)
            |> maybe_where_for_you_since_like_id(since_like_id)

          objects_with_like_ids =
            Repo.all(query,
              telemetry_options: [feature: :timeline, name: :list_for_you_statuses]
            )

          objects =
            Enum.map(objects_with_like_ids, fn {object, like_id} ->
              %{object | internal: Map.put(object.internal || %{}, "for_you_like_id", like_id)}
            end)

          {objects, %{count: length(objects), name: :list_for_you_statuses}}
        end
      )
    end
  end

  def list_for_you_statuses(_actor_ap_id, _opts), do: []

  defp maybe_where_for_you_max_like_id(query, max_like_id) when is_binary(max_like_id) do
    max_like_id = String.trim(max_like_id)

    if flake_id?(max_like_id) do
      from([_o, lr] in query, where: lr.like_id < ^max_like_id)
    else
      query
    end
  end

  defp maybe_where_for_you_max_like_id(query, _max_like_id), do: query

  defp maybe_where_for_you_since_like_id(query, since_like_id) when is_binary(since_like_id) do
    since_like_id = String.trim(since_like_id)

    if flake_id?(since_like_id) do
      from([_o, lr] in query, where: lr.like_id > ^since_like_id)
    else
      query
    end
  end

  defp maybe_where_for_you_since_like_id(query, _since_like_id), do: query

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

  def list_visible_statuses_by_actor(actor, viewer, opts)
      when is_binary(actor) and is_list(opts) do
    limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()
    max_id = Keyword.get(opts, :max_id)
    since_id = Keyword.get(opts, :since_id)

    viewer_ap_id =
      case viewer do
        %Egregoros.User{ap_id: ap_id} when is_binary(ap_id) -> ap_id
        ap_id when is_binary(ap_id) -> ap_id
        _ -> nil
      end

    :telemetry.span(
      [:egregoros, :timeline, :read],
      %{name: :list_visible_statuses_by_actor, limit: limit},
      fn ->
        query =
          from(o in Object,
            where: o.type in ^@status_types and o.actor == ^actor,
            order_by: [desc: o.id],
            limit: ^limit
          )
          |> where_announces_have_object()
          |> where_visible_on_profile(actor, viewer_ap_id)
          |> maybe_where_max_id(max_id)
          |> maybe_where_since_id(since_id)

        objects =
          Repo.all(query,
            telemetry_options: [feature: :timeline, name: :list_visible_statuses_by_actor]
          )

        {objects, %{count: length(objects), name: :list_visible_statuses_by_actor}}
      end
    )
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
        where: o.type == "Note" and o.in_reply_to_ap_id in ^parent_ap_ids,
        group_by: o.in_reply_to_ap_id,
        select: {o.in_reply_to_ap_id, count(o.id)}
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

  def thread_ancestors(%Object{ap_id: ap_id}, limit)
      when is_binary(ap_id) and is_integer(limit) and limit > 0 do
    list_thread_ancestors_by_ap_id(ap_id, limit)
  end

  def thread_ancestors(_object, _limit), do: []

  def thread_descendants(object, limit \\ 50)

  def thread_descendants(%Object{ap_id: ap_id} = object, limit)
      when is_binary(ap_id) and is_integer(limit) and limit > 0 do
    case list_thread_descendants_by_context(object, limit) do
      [] -> list_thread_descendants_by_ap_id(ap_id, limit)
      descendants -> descendants
    end
  end

  def thread_descendants(_object, _limit), do: []

  defp list_thread_ancestors_by_ap_id(object_ap_id, limit)
       when is_binary(object_ap_id) and is_integer(limit) and limit > 0 do
    initial_query =
      from(o in Object,
        where: o.ap_id == ^object_ap_id,
        select: %{
          ap_id: o.ap_id,
          in_reply_to_ap_id: o.in_reply_to_ap_id,
          depth: 0,
          visited_ap_ids: fragment("ARRAY[?]::text[]", o.ap_id)
        }
      )

    recursion_query =
      from(o in Object,
        join: t in "thread_ancestors",
        on: o.ap_id == t.in_reply_to_ap_id,
        where: t.depth < ^limit and fragment("NOT (? = ANY(?))", o.ap_id, t.visited_ap_ids),
        select: %{
          ap_id: o.ap_id,
          in_reply_to_ap_id: o.in_reply_to_ap_id,
          depth: t.depth + 1,
          visited_ap_ids: fragment("array_append(?, ?)", t.visited_ap_ids, o.ap_id)
        }
      )

    cte_query = Ecto.Query.union_all(initial_query, ^recursion_query)

    from(o in Object,
      join: t in "thread_ancestors",
      on: o.ap_id == t.ap_id,
      where: t.depth > 0,
      order_by: [desc: t.depth],
      limit: ^limit,
      select: o
    )
    |> recursive_ctes(true)
    |> with_cte("thread_ancestors", as: ^cte_query)
    |> Repo.all()
  end

  defp list_thread_ancestors_by_ap_id(_object_ap_id, _limit), do: []

  defp list_thread_descendants_by_ap_id(object_ap_id, limit)
       when is_binary(object_ap_id) and is_integer(limit) and limit > 0 do
    initial_query =
      from(o in Object,
        where: o.ap_id == ^object_ap_id,
        select: %{
          id: o.id,
          ap_id: o.ap_id,
          depth: 0,
          path_ids: fragment("ARRAY[?]::uuid[]", o.id)
        }
      )

    recursion_query =
      from(o in Object,
        join: t in "thread_descendants",
        on: o.in_reply_to_ap_id == t.ap_id,
        where:
          o.type in ^@status_types and t.depth < ^limit and
            fragment("NOT (? = ANY(?))", o.id, t.path_ids),
        select: %{
          id: o.id,
          ap_id: o.ap_id,
          depth: t.depth + 1,
          path_ids: fragment("array_append(?, ?)", t.path_ids, o.id)
        }
      )

    cte_query = Ecto.Query.union_all(initial_query, ^recursion_query)

    from(o in Object,
      join: t in "thread_descendants",
      on: o.id == t.id,
      where: t.depth > 0,
      order_by: [asc: t.path_ids],
      limit: ^limit,
      select: o
    )
    |> recursive_ctes(true)
    |> with_cte("thread_descendants", as: ^cte_query)
    |> Repo.all()
  end

  defp list_thread_descendants_by_ap_id(_object_ap_id, _limit), do: []

  defp list_thread_descendants_by_context(%Object{in_reply_to_ap_id: in_reply_to_ap_id}, _limit)
       when is_binary(in_reply_to_ap_id) and in_reply_to_ap_id != "" do
    []
  end

  defp list_thread_descendants_by_context(%Object{ap_id: ap_id, data: %{} = data}, limit)
       when is_binary(ap_id) and is_integer(limit) and limit > 0 do
    context =
      case Map.get(data, "context") do
        context when is_binary(context) ->
          context = String.trim(context)
          if context == "", do: nil, else: context

        _ ->
          nil
      end

    if is_binary(context) do
      from(o in Object,
        where: o.type in ^@status_types and o.context == ^context,
        where: o.ap_id != ^ap_id,
        order_by: [asc: o.published, asc: o.id],
        limit: ^limit,
        select: o
      )
      |> Repo.all()
    else
      []
    end
  end

  defp list_thread_descendants_by_context(_object, _limit), do: []

  def list_replies_to(object_ap_id, opts \\ [])
      when is_binary(object_ap_id) and is_list(opts) do
    limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()

    from(o in Object,
      where: o.type in ^@status_types and o.in_reply_to_ap_id == ^object_ap_id,
      order_by: [asc: o.id],
      limit: ^limit
    )
    |> Repo.all()
  end

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

  defp maybe_where_max_id(query, max_id) when is_binary(max_id) do
    max_id = String.trim(max_id)

    if flake_id?(max_id) do
      from(o in query, where: o.id < ^max_id)
    else
      query
    end
  end

  defp maybe_where_max_id(query, _max_id), do: query

  defp maybe_where_since_id(query, since_id) when is_binary(since_id) do
    since_id = String.trim(since_id)

    if flake_id?(since_id) do
      from(o in query, where: o.id > ^since_id)
    else
      query
    end
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
          # Preserve existing internal state (e.g. polls) while adding auxiliary types.
          |> merge_internal(object)

        update_object(object, attrs)
    end
  end

  defp resolve_conflict(_other, %Object{} = object, _attrs, _changeset), do: {:ok, object}

  defp merge_internal(attrs, %Object{internal: existing_internal}) when is_map(attrs) do
    incoming_internal = Map.get(attrs, :internal) || Map.get(attrs, "internal")

    if is_map(incoming_internal) do
      merged_internal = Map.merge(existing_internal || %{}, incoming_internal)

      attrs
      |> Map.delete("internal")
      |> Map.put(:internal, merged_internal)
    else
      attrs
    end
  end

  defp ap_id_mismatch?(%Object{ap_id: existing}, attrs)
       when is_map(attrs) and is_binary(existing) do
    case Map.get(attrs, :ap_id) || Map.get(attrs, "ap_id") do
      nil -> false
      value when is_binary(value) -> String.trim(value) != "" and String.trim(value) != existing
      _ -> true
    end
  end

  defp ap_id_mismatch?(_object, _attrs), do: false

  defp type_mismatch?(%Object{type: existing}, attrs)
       when is_map(attrs) and is_binary(existing) do
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

  defp flake_id?(id) when is_binary(id) do
    id = String.trim(id)

    cond do
      id == "" ->
        false

      byte_size(id) < 18 ->
        false

      true ->
        try do
          match?(<<_::128>>, FlakeId.from_string(id))
        rescue
          _ -> false
        end
    end
  end

  defp flake_id?(_id), do: false
end
