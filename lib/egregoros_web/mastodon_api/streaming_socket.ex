defmodule EgregorosWeb.MastodonAPI.StreamingSocket do
  @behaviour WebSock

  alias Egregoros.Notifications
  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Relationships
  alias Egregoros.Timeline
  alias Egregoros.User
  alias EgregorosWeb.MastodonAPI.NotificationRenderer
  alias EgregorosWeb.MastodonAPI.StatusRenderer
  alias EgregorosWeb.MastodonAPI.StreamingStreams

  @heartbeat_interval_ms 30_000
  @seen_ap_id_limit 500

  @impl true
  def init(state) when is_map(state) do
    streams =
      state
      |> Map.get(:streams, [])
      |> List.wrap()
      |> Enum.map(&to_string/1)
      |> MapSet.new()

    state =
      state
      |> Map.put(:streams, streams)
      |> Map.put_new(:home_actor_ids, MapSet.new())
      |> Map.put_new(:timeline_public_subscribed, false)
      |> Map.put_new(:timeline_user_subscribed, false)
      |> Map.put_new(:notifications_subscribed, false)
      |> Map.put_new(:seen_ap_ids, {MapSet.new(), :queue.new()})
      |> sync_subscriptions()
      |> schedule_heartbeat()

    {:ok, state}
  end

  @impl true
  def handle_in({payload, opcode: :text}, state) when is_binary(payload) and is_map(state) do
    with {:ok, %{} = event} <- Jason.decode(payload) do
      handle_client_event(event, state)
    else
      _ -> {:ok, state}
    end
  end

  def handle_in({_payload, opcode: _opcode}, state) when is_map(state) do
    {:ok, state}
  end

  @impl true
  def handle_info(:heartbeat, state) when is_map(state) do
    {:push, {:ping, ""}, schedule_heartbeat(state)}
  end

  @impl true
  def handle_info({:post_created, %Object{type: "Announce"} = object}, state)
      when is_map(state) do
    announced_ap_id =
      case object.object do
        value when is_binary(value) -> String.trim(value)
        _ -> ""
      end

    if announced_ap_id != "" and Objects.get_by_ap_id(announced_ap_id) == nil do
      {:ok, state}
    else
      handle_post_created(object, state)
    end
  end

  def handle_info({:post_created, %Object{} = object}, state) when is_map(state) do
    handle_post_created(object, state)
  end

  @impl true
  def handle_info(
        {:notification_created, %Object{} = activity},
        %{current_user: %User{} = user} = state
      ) do
    case streams_for_notification(state) do
      [] ->
        {:ok, state}

      streams ->
        notification_json =
          activity
          |> NotificationRenderer.render_notification(user)
          |> Jason.encode!()

        push_stream_events("notification", notification_json, streams, state)
    end
  end

  def handle_info(_message, state) when is_map(state) do
    {:ok, state}
  end

  defp handle_post_created(%Object{} = object, state) when is_map(state) do
    case remember_seen_ap_id(state, object.ap_id) do
      {:skip, state} ->
        {:ok, state}

      {:ok, state} ->
        case streams_for_status(object, state) do
          [] ->
            {:ok, state}

          streams ->
            status_json = render_status_json(object, state)
            push_stream_events("update", status_json, streams, state)
        end
    end
  end

  defp handle_client_event(%{"type" => "subscribe", "stream" => stream}, state)
       when is_binary(stream) and is_map(state) do
    stream = String.trim(stream)

    cond do
      stream == "" or stream not in StreamingStreams.known_streams() ->
        reply = encode_error("Unknown stream type", 400)
        {:push, {:text, reply}, state}

      MapSet.member?(state.streams, stream) ->
        {:ok, state}

      stream in StreamingStreams.user_streams() and state.current_user == nil ->
        reply = encode_error("Missing access token", 401)
        {:push, {:text, reply}, state}

      true ->
        new_state =
          state
          |> Map.update!(:streams, &MapSet.put(&1, stream))
          |> sync_subscriptions()

        {:ok, new_state}
    end
  end

  defp handle_client_event(%{"type" => "unsubscribe", "stream" => stream}, state)
       when is_binary(stream) and is_map(state) do
    stream = String.trim(stream)

    cond do
      stream == "" or stream not in StreamingStreams.known_streams() ->
        {:ok, state}

      not MapSet.member?(state.streams, stream) ->
        {:ok, state}

      true ->
        new_state =
          state
          |> Map.update!(:streams, &MapSet.delete(&1, stream))
          |> sync_subscriptions()

        {:ok, new_state}
    end
  end

  defp handle_client_event(_event, state) when is_map(state) do
    {:ok, state}
  end

  defp sync_subscriptions(%{streams: %MapSet{} = streams} = state) do
    state
    |> maybe_subscribe_timeline_public(streams)
    |> maybe_subscribe_timeline_user(streams)
    |> maybe_subscribe_notifications(streams)
    |> maybe_unsubscribe_timeline_public(streams)
    |> maybe_unsubscribe_timeline_user(streams)
    |> maybe_unsubscribe_notifications(streams)
    |> maybe_put_home_actor_ids(streams)
  end

  defp maybe_subscribe_timeline_public(%{timeline_public_subscribed: true} = state, _streams),
    do: state

  defp maybe_subscribe_timeline_public(state, streams) do
    if Enum.any?(streams, &(&1 in ["public", "public:local"])) do
      Phoenix.PubSub.subscribe(Egregoros.PubSub, Timeline.public_topic())
      Map.put(state, :timeline_public_subscribed, true)
    else
      state
    end
  end

  defp maybe_subscribe_timeline_user(%{timeline_user_subscribed: true} = state, _streams),
    do: state

  defp maybe_subscribe_timeline_user(%{current_user: %User{} = user} = state, streams) do
    if MapSet.member?(streams, "user") do
      Phoenix.PubSub.subscribe(Egregoros.PubSub, Timeline.user_topic(user.ap_id))
      Map.put(state, :timeline_user_subscribed, true)
    else
      state
    end
  end

  defp maybe_subscribe_timeline_user(state, _streams), do: state

  defp maybe_subscribe_notifications(%{notifications_subscribed: true} = state, _streams),
    do: state

  defp maybe_subscribe_notifications(%{current_user: %User{} = user} = state, streams) do
    if Enum.any?(streams, &(&1 in StreamingStreams.notification_streams())) do
      Notifications.subscribe(user.ap_id)
      Map.put(state, :notifications_subscribed, true)
    else
      state
    end
  end

  defp maybe_subscribe_notifications(state, _streams), do: state

  defp maybe_unsubscribe_timeline_public(%{timeline_public_subscribed: false} = state, _streams),
    do: state

  defp maybe_unsubscribe_timeline_public(state, streams) do
    if Enum.any?(streams, &(&1 in ["public", "public:local"])) do
      state
    else
      Phoenix.PubSub.unsubscribe(Egregoros.PubSub, Timeline.public_topic())
      Map.put(state, :timeline_public_subscribed, false)
    end
  end

  defp maybe_unsubscribe_timeline_user(%{timeline_user_subscribed: false} = state, _streams),
    do: state

  defp maybe_unsubscribe_timeline_user(%{current_user: %User{} = user} = state, streams) do
    if MapSet.member?(streams, "user") do
      state
    else
      Phoenix.PubSub.unsubscribe(Egregoros.PubSub, Timeline.user_topic(user.ap_id))
      Map.put(state, :timeline_user_subscribed, false)
    end
  end

  defp maybe_unsubscribe_timeline_user(state, _streams), do: state

  defp maybe_unsubscribe_notifications(%{notifications_subscribed: false} = state, _streams),
    do: state

  defp maybe_unsubscribe_notifications(%{current_user: %User{} = user} = state, streams) do
    if Enum.any?(streams, &(&1 in StreamingStreams.notification_streams())) do
      state
    else
      Phoenix.PubSub.unsubscribe(Egregoros.PubSub, "notifications:" <> user.ap_id)
      Map.put(state, :notifications_subscribed, false)
    end
  end

  defp maybe_unsubscribe_notifications(state, _streams), do: state

  defp maybe_put_home_actor_ids(%{current_user: %User{} = user} = state, streams) do
    if MapSet.member?(streams, "user") do
      Map.put(state, :home_actor_ids, home_actor_ids(user))
    else
      Map.put(state, :home_actor_ids, MapSet.new())
    end
  end

  defp maybe_put_home_actor_ids(state, _streams), do: state

  defp streams_for_status(%Object{} = object, %{streams: %MapSet{} = streams} = state) do
    streams
    |> Enum.filter(fn
      "user" -> deliver_user_status?(object, state)
      "public" -> deliver_public_status?(object)
      "public:local" -> deliver_public_status?(object) and object.local
      _ -> false
    end)
  end

  defp streams_for_notification(%{streams: %MapSet{} = streams}) do
    streams
    |> Enum.filter(&(&1 in StreamingStreams.notification_streams()))
  end

  defp deliver_public_status?(%Object{type: type} = object) when type in ~w(Note Announce) do
    Objects.publicly_listed?(object)
  end

  defp deliver_public_status?(_object), do: false

  defp deliver_user_status?(
         %Object{type: type} = object,
         %{current_user: %User{} = user, home_actor_ids: %MapSet{} = actor_ids}
       )
       when type in ~w(Note Announce) do
    cond do
      is_binary(object.actor) and MapSet.member?(actor_ids, object.actor) and
          Objects.visible_to?(object, user) ->
        true

      recipient?(object, user.ap_id) and Objects.visible_to?(object, user) ->
        true

      true ->
        false
    end
  end

  defp deliver_user_status?(_object, _state), do: false

  @recipient_fields ~w(to cc bto bcc audience)

  defp recipient?(%Object{data: %{} = data}, user_ap_id) when is_binary(user_ap_id) do
    user_ap_id = String.trim(user_ap_id)

    if user_ap_id == "" do
      false
    else
      Enum.any?(@recipient_fields, fn field ->
        data
        |> Map.get(field)
        |> List.wrap()
        |> Enum.any?(fn
          %{"id" => id} when is_binary(id) -> String.trim(id) == user_ap_id
          %{id: id} when is_binary(id) -> String.trim(id) == user_ap_id
          id when is_binary(id) -> String.trim(id) == user_ap_id
          _ -> false
        end)
      end)
    end
  end

  defp recipient?(_object, _user_ap_id), do: false

  defp render_status_json(%Object{} = object, state) when is_map(state) do
    case Map.get(state, :current_user) do
      %User{} = user -> StatusRenderer.render_status(object, user)
      _ -> StatusRenderer.render_status(object)
    end
    |> Jason.encode!()
  end

  defp push_stream_events(event, payload, streams, state)
       when is_binary(event) and is_binary(payload) and is_list(streams) and is_map(state) do
    messages =
      Enum.map(streams, fn stream ->
        {:text, encode_event(event, payload, [stream])}
      end)

    case messages do
      [message] -> {:push, message, state}
      _ -> {:push, messages, state}
    end
  end

  defp encode_event(event, payload, stream)
       when is_binary(event) and is_binary(payload) and is_list(stream) do
    Jason.encode!(%{"stream" => stream, "event" => event, "payload" => payload})
  end

  defp encode_error(message, status) when is_binary(message) and is_integer(status) do
    Jason.encode!(%{"error" => message, "status" => status})
  end

  defp home_actor_ids(%User{} = user) do
    followed_actor_ids =
      user.ap_id
      |> Relationships.list_follows_by_actor()
      |> Enum.map(& &1.object)
      |> Enum.filter(&is_binary/1)

    [user.ap_id | followed_actor_ids]
    |> Enum.uniq()
    |> MapSet.new()
  end

  defp schedule_heartbeat(state) when is_map(state) do
    _ = Process.send_after(self(), :heartbeat, @heartbeat_interval_ms)
    state
  end

  defp remember_seen_ap_id(state, ap_id) when is_map(state) and is_binary(ap_id) do
    ap_id = String.trim(ap_id)

    if ap_id == "" do
      {:ok, state}
    else
      {seen_set, queue} = Map.get(state, :seen_ap_ids, {MapSet.new(), :queue.new()})

      if MapSet.member?(seen_set, ap_id) do
        {:skip, state}
      else
        queue = :queue.in(ap_id, queue)
        seen_set = MapSet.put(seen_set, ap_id)

        {seen_set, queue} =
          if :queue.len(queue) > @seen_ap_id_limit do
            {{:value, old}, queue} = :queue.out(queue)
            {MapSet.delete(seen_set, old), queue}
          else
            {seen_set, queue}
          end

        {:ok, Map.put(state, :seen_ap_ids, {seen_set, queue})}
      end
    end
  end

  defp remember_seen_ap_id(state, _ap_id) when is_map(state), do: {:ok, state}
end
