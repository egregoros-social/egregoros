defmodule PleromaReduxWeb.MastodonAPI.StatusRenderer do
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

  def render_status(%Object{} = object, nil) do
    account = account_from_actor(object.actor)
    render_status_with_account(object, account, nil)
  end

  def render_status(%Object{} = object, %User{} = current_user) do
    account = account_from_actor(object.actor)
    render_status_with_account(object, account, current_user)
  end

  def render_statuses(objects) when is_list(objects) do
    Enum.map(objects, &render_status/1)
  end

  def render_statuses(objects, current_user) when is_list(objects) do
    Enum.map(objects, &render_status(&1, current_user))
  end

  defp render_status_with_account(object, account, current_user) do
    favourites_count = Relationships.count_by_type_object("Like", object.ap_id)
    reblogs_count = Relationships.count_by_type_object("Announce", object.ap_id)

    favourited =
      current_user != nil and
        Relationships.get_by_type_actor_object("Like", current_user.ap_id, object.ap_id) != nil

    reblogged =
      current_user != nil and
        Relationships.get_by_type_actor_object("Announce", current_user.ap_id, object.ap_id) !=
          nil

    %{
      "id" => Integer.to_string(object.id),
      "uri" => object.ap_id,
      "url" => object.ap_id,
      "visibility" => "public",
      "sensitive" => false,
      "spoiler_text" => "",
      "content" => Map.get(object.data, "content", ""),
      "account" => account,
      "created_at" => format_datetime(object),
      "media_attachments" => media_attachments(object),
      "mentions" => [],
      "tags" => [],
      "emojis" => [],
      "reblogs_count" => reblogs_count,
      "favourites_count" => favourites_count,
      "replies_count" => 0,
      "favourited" => favourited,
      "reblogged" => reblogged,
      "muted" => false,
      "bookmarked" => false,
      "pinned" => false,
      "in_reply_to_id" => nil,
      "in_reply_to_account_id" => nil,
      "reblog" => nil,
      "poll" => nil,
      "card" => nil,
      "language" => nil,
      "pleroma" => %{
        "emoji_reactions" => emoji_reactions(object, current_user)
      }
    }
  end

  defp account_from_actor(actor) when is_binary(actor) do
    case Users.get_by_ap_id(actor) do
      %User{} = user ->
        AccountRenderer.render_account(user)

      _ ->
        %{
          "id" => actor,
          "username" => fallback_username(actor),
          "acct" => fallback_username(actor)
        }
    end
  end

  defp account_from_actor(_),
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

  defp format_datetime(%Object{inserted_at: %NaiveDateTime{} = dt}) do
    dt
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601()
  end

  defp format_datetime(%Object{}), do: DateTime.utc_now() |> DateTime.to_iso8601()

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

  defp emoji_reactions(%Object{} = object, %User{} = current_user) do
    object.ap_id
    |> Relationships.emoji_reaction_counts()
    |> Enum.map(fn {type, count} ->
      emoji = String.replace_prefix(type, "EmojiReact:", "")

      %{
        "name" => emoji,
        "count" => count,
        "me" =>
          Relationships.get_by_type_actor_object(type, current_user.ap_id, object.ap_id) != nil
      }
    end)
  end

  defp emoji_reactions(%Object{} = object, _current_user) do
    object.ap_id
    |> Relationships.emoji_reaction_counts()
    |> Enum.map(fn {type, count} ->
      %{
        "name" => String.replace_prefix(type, "EmojiReact:", ""),
        "count" => count,
        "me" => false
      }
    end)
  end
end
