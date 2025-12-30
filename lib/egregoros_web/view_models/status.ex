defmodule EgregorosWeb.ViewModels.Status do
  @moduledoc false

  alias Egregoros.Relationships
  alias Egregoros.User
  alias EgregorosWeb.SafeMediaURL
  alias EgregorosWeb.ViewModels.Actor

  @reaction_emojis ["🔥", "👍", "❤️"]

  def decorate(%{type: "Note"} = object, current_user) do
    %{
      object: object,
      actor: Actor.card(object.actor),
      attachments: attachments_for_object(object),
      likes_count: Relationships.count_by_type_object("Like", object.ap_id),
      liked?: liked_by_user?(object, current_user),
      reposts_count: Relationships.count_by_type_object("Announce", object.ap_id),
      reposted?: reposted_by_user?(object, current_user),
      bookmarked?: bookmarked_by_user?(object, current_user),
      reactions: reactions_for_object(object, current_user)
    }
  end

  def decorate(object, current_user) when is_map(object) do
    %{
      object: object,
      actor: Actor.card(Map.get(object, :actor)),
      attachments: [],
      likes_count: 0,
      liked?: false,
      reposts_count: 0,
      reposted?: false,
      bookmarked?: false,
      reactions: reactions_for_object(object, current_user)
    }
  end

  def decorate_many(objects, current_user) when is_list(objects) do
    Enum.map(objects, &decorate(&1, current_user))
  end

  def reaction_emojis, do: @reaction_emojis

  defp liked_by_user?(_object, nil), do: false

  defp liked_by_user?(object, %User{} = current_user) do
    Relationships.get_by_type_actor_object("Like", current_user.ap_id, object.ap_id) != nil
  end

  defp reposted_by_user?(_object, nil), do: false

  defp reposted_by_user?(object, %User{} = current_user) do
    Relationships.get_by_type_actor_object("Announce", current_user.ap_id, object.ap_id) != nil
  end

  defp bookmarked_by_user?(_object, nil), do: false

  defp bookmarked_by_user?(object, %User{} = current_user) do
    Relationships.get_by_type_actor_object("Bookmark", current_user.ap_id, object.ap_id) != nil
  end

  defp reactions_for_object(%{ap_id: ap_id}, current_user) when is_binary(ap_id) do
    counts =
      ap_id
      |> Relationships.emoji_reaction_counts()
      |> Enum.reduce(%{}, fn {type, count}, acc ->
        emoji = String.replace_prefix(type, "EmojiReact:", "")

        if emoji == "" do
          acc
        else
          Map.put(acc, emoji, count)
        end
      end)

    emojis =
      @reaction_emojis
      |> Kernel.++(Map.keys(counts))
      |> Enum.uniq()

    for emoji <- emojis, into: %{} do
      relationship_type = "EmojiReact:" <> emoji

      {emoji,
       %{
         count: Map.get(counts, emoji, 0),
         reacted?: reacted_by_user?(ap_id, current_user, relationship_type)
       }}
    end
  end

  defp reactions_for_object(_object, _current_user) do
    for emoji <- @reaction_emojis, into: %{} do
      {emoji, %{count: 0, reacted?: false}}
    end
  end

  defp reacted_by_user?(_object_ap_id, nil, _relationship_type), do: false

  defp reacted_by_user?(object_ap_id, %User{} = current_user, relationship_type)
       when is_binary(object_ap_id) and is_binary(relationship_type) do
    Relationships.get_by_type_actor_object(relationship_type, current_user.ap_id, object_ap_id) !=
      nil
  end

  defp attachments_for_object(%{data: %{} = data}) do
    data
    |> Map.get("attachment")
    |> List.wrap()
    |> Enum.filter(&is_map/1)
    |> Enum.map(&attachment_view_model/1)
    |> Enum.reject(&is_nil/1)
  end

  defp attachments_for_object(_object), do: []

  defp attachment_view_model(%{} = attachment) do
    href =
      attachment
      |> Map.get("url")
      |> List.wrap()
      |> Enum.find_value(&attachment_href/1)
      |> SafeMediaURL.safe()

    media_type =
      cond do
        is_binary(Map.get(attachment, "mediaType")) ->
          Map.get(attachment, "mediaType")

        true ->
          attachment
          |> Map.get("url")
          |> List.wrap()
          |> Enum.find_value(&attachment_media_type/1)
      end

    description =
      attachment
      |> Map.get("name", "")
      |> to_string()
      |> String.trim()

    if is_binary(href) and href != "" do
      %{
        href: href,
        media_type: media_type,
        description: description
      }
    else
      nil
    end
  end

  defp attachment_href(%{"href" => href}) when is_binary(href), do: href
  defp attachment_href(href) when is_binary(href), do: href
  defp attachment_href(_), do: nil

  defp attachment_media_type(%{"mediaType" => media_type}) when is_binary(media_type),
    do: media_type

  defp attachment_media_type(_), do: nil
end
