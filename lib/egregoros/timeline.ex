defmodule Egregoros.Timeline do
  @moduledoc """
  Timeline feed backed by objects and PubSub broadcasts.
  """

  alias Egregoros.Objects
  alias Egregoros.Relationships
  alias Egregoros.User
  alias Egregoros.Users

  @as_public "https://www.w3.org/ns/activitystreams#Public"
  @public_topic "timeline:public"
  @user_topic_prefix "timeline:user:"

  def public_topic, do: @public_topic

  def user_topic(user_ap_id) when is_binary(user_ap_id),
    do: @user_topic_prefix <> user_ap_id

  def user_topic(_), do: @user_topic_prefix <> "unknown"

  def subscribe, do: subscribe_public()

  def subscribe_public do
    Phoenix.PubSub.subscribe(Egregoros.PubSub, @public_topic)
  end

  def subscribe_user(%User{ap_id: ap_id}) when is_binary(ap_id), do: subscribe_user(ap_id)

  def subscribe_user(user_ap_id) when is_binary(user_ap_id) do
    Phoenix.PubSub.subscribe(Egregoros.PubSub, user_topic(user_ap_id))
  end

  def unsubscribe_public do
    Phoenix.PubSub.unsubscribe(Egregoros.PubSub, @public_topic)
  end

  def unsubscribe_user(%User{ap_id: ap_id}) when is_binary(ap_id), do: unsubscribe_user(ap_id)

  def unsubscribe_user(user_ap_id) when is_binary(user_ap_id) do
    Phoenix.PubSub.unsubscribe(Egregoros.PubSub, user_topic(user_ap_id))
  end

  def list_posts do
    Objects.list_notes()
  end

  def broadcast_post(%Egregoros.Object{} = object) do
    broadcast_topics_for_object(object)
    |> Enum.each(fn topic ->
      Phoenix.PubSub.broadcast(Egregoros.PubSub, topic, {:post_created, object})
    end)

    :ok
  end

  def broadcast_post(_object), do: :ok

  def broadcast_post_updated(%Egregoros.Object{} = object) do
    broadcast_topics_for_object(object)
    |> Enum.each(fn topic ->
      Phoenix.PubSub.broadcast(Egregoros.PubSub, topic, {:post_updated, object})
    end)

    :ok
  end

  def broadcast_post_updated(_object), do: :ok

  def reset do
    Objects.delete_all_notes()
  end

  defp broadcast_topics_for_object(%Egregoros.Object{actor: actor} = object)
       when is_binary(actor) do
    public_topics =
      if Objects.publicly_listed?(object) do
        [@public_topic]
      else
        []
      end

    recipient_ap_ids = recipient_actor_ids(object)
    follower_ap_ids = local_follower_ap_ids(actor)

    user_ap_ids =
      [actor | recipient_ap_ids ++ follower_ap_ids]
      |> Enum.uniq()
      |> local_user_ap_ids()
      |> Enum.filter(fn ap_id ->
        ap_id == actor or ap_id in recipient_ap_ids or ap_id in follower_ap_ids
      end)
      |> Enum.filter(fn ap_id ->
        cond do
          ap_id == actor ->
            true

          ap_id in recipient_ap_ids ->
            Objects.visible_to?(object, ap_id)

          ap_id in follower_ap_ids ->
            Objects.visible_to?(object, ap_id)

          true ->
            false
        end
      end)

    user_topics = Enum.map(user_ap_ids, &user_topic/1)

    Enum.uniq(public_topics ++ user_topics)
  end

  defp broadcast_topics_for_object(_object), do: []

  defp local_user_ap_ids(ap_ids) when is_list(ap_ids) do
    ap_ids
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Users.list_by_ap_ids()
    |> Enum.filter(&(&1.local == true))
    |> Enum.map(& &1.ap_id)
  end

  defp local_follower_ap_ids(actor_ap_id) when is_binary(actor_ap_id) do
    actor_ap_id
    |> Relationships.list_follows_to()
    |> Enum.map(& &1.actor)
    |> local_user_ap_ids()
  end

  @recipient_fields ~w(to cc bto bcc audience)

  defp recipient_actor_ids(%Egregoros.Object{data: %{} = data}) do
    @recipient_fields
    |> Enum.flat_map(fn field ->
      data
      |> Map.get(field)
      |> List.wrap()
      |> Enum.map(&extract_recipient_id/1)
    end)
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or &1 == @as_public or String.ends_with?(&1, "/followers")))
    |> Enum.uniq()
  end

  defp recipient_actor_ids(_object), do: []

  defp extract_recipient_id(%{"id" => id}) when is_binary(id), do: id
  defp extract_recipient_id(%{id: id}) when is_binary(id), do: id
  defp extract_recipient_id(id) when is_binary(id), do: id
  defp extract_recipient_id(_recipient), do: nil
end
