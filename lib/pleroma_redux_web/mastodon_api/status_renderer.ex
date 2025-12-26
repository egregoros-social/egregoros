defmodule PleromaReduxWeb.MastodonAPI.StatusRenderer do
  alias PleromaRedux.HTML
  alias PleromaRedux.Object
  alias PleromaRedux.Objects
  alias PleromaRedux.Relationships
  alias PleromaRedux.User
  alias PleromaRedux.Users
  alias PleromaReduxWeb.URL
  alias PleromaReduxWeb.MastodonAPI.AccountRenderer

  def render_status(%Object{} = object) do
    render_status(object, nil)
  end

  def render_status(%Object{} = object, current_user) do
    case render_statuses([object], current_user) do
      [rendered] -> rendered
      _ -> %{"id" => Integer.to_string(object.id)}
    end
  end

  def render_statuses(objects) when is_list(objects) do
    render_statuses(objects, nil)
  end

  def render_statuses(objects, current_user) when is_list(objects) do
    ctx = rendering_context(objects, current_user)
    Enum.map(objects, &render_status_with_context(&1, ctx))
  end

  defp rendering_context(objects, current_user) when is_list(objects) do
    reblog_ap_ids =
      objects
      |> Enum.filter(&match?(%Object{type: "Announce"}, &1))
      |> Enum.map(& &1.object)
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    reblogs_by_ap_id =
      reblog_ap_ids
      |> Objects.list_by_ap_ids()
      |> Map.new(&{&1.ap_id, &1})

    all_objects =
      objects
      |> Kernel.++(Map.values(reblogs_by_ap_id))
      |> Enum.uniq_by(& &1.ap_id)

    object_ap_ids =
      all_objects
      |> Enum.map(& &1.ap_id)
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    actor_ap_ids =
      all_objects
      |> Enum.map(& &1.actor)
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    users_by_ap_id =
      actor_ap_ids
      |> Users.list_by_ap_ids()
      |> Map.new(&{&1.ap_id, &1})

    followers_counts = Relationships.count_by_type_objects("Follow", actor_ap_ids)
    following_counts = Relationships.count_by_type_actors("Follow", actor_ap_ids)
    statuses_counts = Objects.count_notes_by_actors(actor_ap_ids)

    accounts_by_actor =
      Enum.reduce(users_by_ap_id, %{}, fn {ap_id, user}, acc ->
        account =
          AccountRenderer.render_account(user,
            followers_count: Map.get(followers_counts, ap_id, 0),
            following_count: Map.get(following_counts, ap_id, 0),
            statuses_count: Map.get(statuses_counts, ap_id, 0)
          )

        Map.put(acc, ap_id, account)
      end)

    status_counts = Relationships.count_by_types_objects(["Like", "Announce"], object_ap_ids)

    me_relationships =
      case current_user do
        %User{ap_id: ap_id} when is_binary(ap_id) ->
          Relationships.list_by_types_actor_objects(["Like", "Announce"], ap_id, object_ap_ids)

        _ ->
          MapSet.new()
      end

    emoji_counts = Relationships.emoji_reaction_counts_for_objects(object_ap_ids)

    emoji_me_relationships =
      case current_user do
        %User{ap_id: ap_id} when is_binary(ap_id) ->
          Relationships.emoji_reactions_by_actor_for_objects(ap_id, object_ap_ids)

        _ ->
          MapSet.new()
      end

    %{
      current_user: current_user,
      reblogs_by_ap_id: reblogs_by_ap_id,
      accounts_by_actor: accounts_by_actor,
      status_counts: status_counts,
      me_relationships: me_relationships,
      emoji_counts: emoji_counts,
      emoji_me_relationships: emoji_me_relationships
    }
  end

  defp render_status_with_context(%Object{type: "Announce"} = object, ctx) do
    render_reblog(object, ctx)
  end

  defp render_status_with_context(%Object{} = object, ctx) do
    account = account_from_actor(object.actor, ctx)
    render_status_with_account(object, account, ctx)
  end

  defp render_status_with_account(object, account, ctx) do
    counts = Map.get(ctx.status_counts, object.ap_id, %{})
    favourites_count = Map.get(counts, "Like", 0)
    reblogs_count = Map.get(counts, "Announce", 0)

    favourited =
      match?(%User{}, ctx.current_user) and
        MapSet.member?(ctx.me_relationships, {"Like", object.ap_id})

    reblogged =
      match?(%User{}, ctx.current_user) and
        MapSet.member?(ctx.me_relationships, {"Announce", object.ap_id})

    {in_reply_to_id, in_reply_to_account_id} = in_reply_to(object)

    %{
      "id" => Integer.to_string(object.id),
      "uri" => object.ap_id,
      "url" => object.ap_id,
      "visibility" => visibility(object),
      "sensitive" => sensitive(object),
      "spoiler_text" => spoiler_text(object),
      "content" => content(object),
      "account" => account,
      "created_at" => format_datetime(object),
      "media_attachments" => media_attachments(object),
      "mentions" => mentions(object),
      "tags" => tags(object),
      "emojis" => emojis(object),
      "reblogs_count" => reblogs_count,
      "favourites_count" => favourites_count,
      "replies_count" => 0,
      "favourited" => favourited,
      "reblogged" => reblogged,
      "muted" => false,
      "bookmarked" => false,
      "pinned" => false,
      "in_reply_to_id" => in_reply_to_id,
      "in_reply_to_account_id" => in_reply_to_account_id,
      "reblog" => nil,
      "poll" => nil,
      "card" => nil,
      "language" => language(object),
      "pleroma" => %{
        "emoji_reactions" => emoji_reactions(object, ctx)
      }
    }
  end

  defp render_reblog(%Object{} = announce, ctx) do
    account = account_from_actor(announce.actor, ctx)

    reblog =
      case announce.object do
        ap_id when is_binary(ap_id) ->
          case Map.get(ctx.reblogs_by_ap_id, ap_id) do
            %Object{} = object -> render_status_with_context(object, ctx)
            _ -> nil
          end

        _ ->
          nil
      end

    %{
      "id" => Integer.to_string(announce.id),
      "uri" => announce.ap_id,
      "url" => announce.ap_id,
      "visibility" =>
        if(is_map(reblog), do: Map.get(reblog, "visibility", "public"), else: "public"),
      "sensitive" => if(is_map(reblog), do: Map.get(reblog, "sensitive", false), else: false),
      "spoiler_text" => "",
      "content" => "",
      "account" => account,
      "created_at" => format_datetime(announce),
      "media_attachments" => [],
      "mentions" => [],
      "tags" => [],
      "emojis" => [],
      "reblogs_count" => if(is_map(reblog), do: Map.get(reblog, "reblogs_count", 0), else: 0),
      "favourites_count" =>
        if(is_map(reblog), do: Map.get(reblog, "favourites_count", 0), else: 0),
      "replies_count" => if(is_map(reblog), do: Map.get(reblog, "replies_count", 0), else: 0),
      "favourited" => if(is_map(reblog), do: Map.get(reblog, "favourited", false), else: false),
      "reblogged" => if(is_map(reblog), do: Map.get(reblog, "reblogged", false), else: false),
      "muted" => false,
      "bookmarked" => false,
      "pinned" => false,
      "in_reply_to_id" => nil,
      "in_reply_to_account_id" => nil,
      "reblog" => reblog,
      "poll" => nil,
      "card" => nil,
      "language" => if(is_map(reblog), do: Map.get(reblog, "language"), else: nil),
      "pleroma" => %{
        "emoji_reactions" => []
      }
    }
  end

  defp account_from_actor(actor, ctx) when is_binary(actor) do
    Map.get(ctx.accounts_by_actor, actor) ||
      %{
        "id" => actor,
        "username" => fallback_username(actor),
        "acct" => fallback_username(actor)
      }
  end

  defp account_from_actor(_actor, _ctx),
    do: %{"id" => "unknown", "username" => "unknown", "acct" => "unknown"}

  defp fallback_username(actor) do
    case URI.parse(actor) do
      %URI{path: path} when is_binary(path) and path != "" ->
        path
        |> String.split("/", trim: true)
        |> List.last()
        |> case do
          nil -> "unknown"
          value -> value
        end

      _ ->
        "unknown"
    end
  end

  defp format_datetime(%Object{published: %DateTime{} = dt}) do
    DateTime.to_iso8601(dt)
  end

  defp format_datetime(%Object{inserted_at: %DateTime{} = dt}), do: DateTime.to_iso8601(dt)

  defp format_datetime(%Object{}), do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp in_reply_to(%Object{} = object) do
    object.data
    |> Map.get("inReplyTo")
    |> in_reply_to_ap_id()
    |> case do
      ap_id when is_binary(ap_id) ->
        case Objects.get_by_ap_id(ap_id) do
          %Object{} = parent ->
            account_id =
              case Users.get_by_ap_id(parent.actor) do
                %User{} = user -> Integer.to_string(user.id)
                _ -> nil
              end

            {Integer.to_string(parent.id), account_id}

          _ ->
            {nil, nil}
        end

      _ ->
        {nil, nil}
    end
  end

  defp in_reply_to(_), do: {nil, nil}

  defp in_reply_to_ap_id(value) when is_binary(value), do: value
  defp in_reply_to_ap_id(%{"id" => id}) when is_binary(id), do: id
  defp in_reply_to_ap_id(_), do: nil

  defp visibility(%Object{} = object) do
    to = object.data |> Map.get("to", []) |> List.wrap()
    cc = object.data |> Map.get("cc", []) |> List.wrap()

    public = "https://www.w3.org/ns/activitystreams#Public"
    followers = object.actor <> "/followers"

    cond do
      public in to ->
        "public"

      public in cc and followers in to ->
        "unlisted"

      followers in to ->
        "private"

      true ->
        "direct"
    end
  end

  defp visibility(_), do: "public"

  defp spoiler_text(%Object{} = object) do
    object.data
    |> Map.get("summary", "")
    |> to_string()
  end

  defp spoiler_text(_), do: ""

  defp sensitive(%Object{} = object) do
    object.data
    |> Map.get("sensitive", false)
    |> case do
      true -> true
      "true" -> true
      _ -> false
    end
  end

  defp sensitive(_), do: false

  defp content(%Object{} = object) do
    raw = Map.get(object.data, "content", "")

    format =
      case object.local do
        false -> :html
        _ -> :text
      end

    HTML.to_safe_html(raw, format: format)
  end

  defp content(_), do: ""

  defp language(%Object{} = object) do
    object.data
    |> Map.get("language")
    |> case do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp language(_), do: nil

  defp media_attachments(%Object{} = object) do
    object.data
    |> Map.get("attachment", [])
    |> List.wrap()
    |> Enum.filter(&is_map/1)
    |> Enum.map(&render_media_attachment/1)
  end

  defp render_media_attachment(%{"id" => ap_id} = attachment) when is_binary(ap_id) do
    object = Objects.get_by_ap_id(ap_id)

    url = attachment_url(attachment)
    description = Map.get(attachment, "name")
    blurhash = Map.get(attachment, "blurhash")

    %{
      "id" => media_id(object, ap_id),
      "type" => mastodon_type(attachment),
      "url" => url,
      "preview_url" => url,
      "remote_url" => nil,
      "meta" => %{},
      "description" => description,
      "blurhash" => blurhash
    }
  end

  defp render_media_attachment(attachment) when is_map(attachment) do
    url = attachment_url(attachment)

    %{
      "id" => Map.get(attachment, "id", "unknown"),
      "type" => mastodon_type(attachment),
      "url" => url,
      "preview_url" => url,
      "remote_url" => nil,
      "meta" => %{},
      "description" => Map.get(attachment, "name"),
      "blurhash" => Map.get(attachment, "blurhash")
    }
  end

  defp media_id(%Object{} = object, _fallback), do: Integer.to_string(object.id)
  defp media_id(_object, fallback), do: fallback

  defp attachment_url(%{"url" => [%{"href" => href} | _]}) when is_binary(href) do
    URL.absolute(href) || href
  end

  defp attachment_url(%{"url" => href}) when is_binary(href) do
    URL.absolute(href) || href
  end

  defp attachment_url(_), do: ""

  defp mastodon_type(%{"mediaType" => media_type}) when is_binary(media_type) do
    mastodon_type_from_mime(media_type)
  end

  defp mastodon_type(%{"url" => [%{"mediaType" => media_type} | _]}) when is_binary(media_type) do
    mastodon_type_from_mime(media_type)
  end

  defp mastodon_type(_), do: "unknown"

  defp mastodon_type_from_mime(mime) when is_binary(mime) do
    cond do
      String.starts_with?(mime, "image/") -> "image"
      String.starts_with?(mime, "video/") -> "video"
      String.starts_with?(mime, "audio/") -> "audio"
      true -> "unknown"
    end
  end

  defp emoji_reactions(%Object{} = object, ctx) do
    ctx.emoji_counts
    |> Map.get(object.ap_id, %{})
    |> Enum.sort_by(fn {type, _count} -> type end)
    |> Enum.map(fn {type, count} ->
      %{
        "name" => String.replace_prefix(type, "EmojiReact:", ""),
        "count" => count,
        "me" =>
          match?(%User{}, ctx.current_user) and
            MapSet.member?(ctx.emoji_me_relationships, {type, object.ap_id})
      }
    end)
  end

  defp mentions(%Object{} = object) do
    object
    |> activity_tags()
    |> Enum.filter(&(Map.get(&1, "type") == "Mention"))
    |> Enum.map(&render_mention/1)
    |> Enum.filter(&is_map/1)
  end

  defp mentions(_), do: []

  defp render_mention(%{} = tag) do
    href =
      case tag do
        %{"href" => href} when is_binary(href) -> href
        %{"id" => href} when is_binary(href) -> href
        _ -> nil
      end

    name =
      case tag do
        %{"name" => name} when is_binary(name) -> name
        _ -> nil
      end

    with href when is_binary(href) <- href do
      case Users.get_by_ap_id(href) do
        %User{} = user ->
          %{
            "id" => Integer.to_string(user.id),
            "username" => user.nickname,
            "url" => href,
            "acct" => acct_for_user(user)
          }

        _ ->
          {username, acct} = mention_username_and_acct(name, href)

          %{
            "id" => href,
            "username" => username,
            "url" => href,
            "acct" => acct
          }
      end
    else
      _ -> nil
    end
  end

  defp render_mention(_), do: nil

  defp mention_username_and_acct(name, href) do
    name =
      case name do
        name when is_binary(name) -> String.trim(name)
        _ -> ""
      end

    name =
      if String.starts_with?(name, "@") do
        String.trim_leading(name, "@")
      else
        name
      end

    case String.split(name, "@", parts: 2, trim: true) do
      [username, host] ->
        {username, "#{username}@#{host}"}

      [username] ->
        {username, acct_for_remote(username, href)}

      _ ->
        username = fallback_username(href)
        {username, acct_for_remote(username, href)}
    end
  end

  defp acct_for_remote(username, ap_id) when is_binary(username) and is_binary(ap_id) do
    case URI.parse(ap_id) do
      %URI{host: host} when is_binary(host) and host != "" -> "#{username}@#{host}"
      _ -> username
    end
  end

  defp acct_for_remote(username, _ap_id) when is_binary(username), do: username
  defp acct_for_remote(_username, _ap_id), do: "unknown"

  defp acct_for_user(%User{local: true, nickname: nickname}) when is_binary(nickname),
    do: nickname

  defp acct_for_user(%User{nickname: nickname, ap_id: ap_id})
       when is_binary(nickname) and is_binary(ap_id) do
    case URI.parse(ap_id) do
      %URI{host: host} when is_binary(host) and host != "" -> "#{nickname}@#{host}"
      _ -> nickname
    end
  end

  defp acct_for_user(_), do: "unknown"

  defp tags(%Object{} = object) do
    object
    |> activity_tags()
    |> Enum.filter(&(Map.get(&1, "type") == "Hashtag"))
    |> Enum.map(&render_hashtag/1)
    |> Enum.filter(&is_map/1)
  end

  defp tags(_), do: []

  defp render_hashtag(%{"name" => name} = tag) when is_binary(name) do
    name =
      name
      |> String.trim()
      |> String.trim_leading("#")
      |> String.downcase()

    href =
      case tag do
        %{"href" => href} when is_binary(href) -> href
        _ -> URL.absolute("/tags/" <> name)
      end

    %{"name" => name, "url" => href}
  end

  defp render_hashtag(_), do: nil

  defp emojis(%Object{} = object) do
    object
    |> activity_tags()
    |> Enum.filter(&(Map.get(&1, "type") == "Emoji"))
    |> Enum.map(&render_custom_emoji/1)
    |> Enum.filter(&is_map/1)
  end

  defp emojis(_), do: []

  defp render_custom_emoji(%{"name" => name, "icon" => icon}) when is_binary(name) do
    shortcode =
      name
      |> String.trim()
      |> String.trim(":")

    url = icon_url(icon)

    if is_binary(url) and shortcode != "" do
      %{
        "shortcode" => shortcode,
        "url" => url,
        "static_url" => url,
        "visible_in_picker" => true
      }
    end
  end

  defp render_custom_emoji(_), do: nil

  defp icon_url(%{"url" => url}) when is_binary(url), do: url

  defp icon_url(%{"url" => [%{"href" => href} | _]}) when is_binary(href), do: href

  defp icon_url(%{"url" => [%{"url" => url} | _]}) when is_binary(url), do: url

  defp icon_url(_), do: nil

  defp activity_tags(%Object{} = object) do
    object.data
    |> Map.get("tag", [])
    |> List.wrap()
    |> Enum.filter(&is_map/1)
  end

  defp activity_tags(_), do: []
end
