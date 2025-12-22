defmodule PleromaReduxWeb.MastodonAPI.StreamingSocket do
  @behaviour WebSock

  alias PleromaRedux.Notifications
  alias PleromaRedux.Object
  alias PleromaRedux.Relationships
  alias PleromaRedux.Timeline
  alias PleromaRedux.User
  alias PleromaReduxWeb.MastodonAPI.NotificationRenderer
  alias PleromaReduxWeb.MastodonAPI.StatusRenderer
  alias PleromaReduxWeb.MastodonAPI.StreamingStreams

  @heartbeat_interval_ms 30_000

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
      |> Map.put_new(:timeline_subscribed, false)
      |> Map.put_new(:notifications_subscribed, false)
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
  def handle_info({:post_created, %Object{} = object}, state) when is_map(state) do
    case streams_for_status(object, state) do
      [] ->
        {:ok, state}

      streams ->
        status_json = render_status_json(object, state)
        push_stream_events("update", status_json, streams, state)
    end
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
    |> maybe_subscribe_timeline(streams)
    |> maybe_subscribe_notifications(streams)
    |> maybe_unsubscribe_timeline(streams)
    |> maybe_unsubscribe_notifications(streams)
    |> maybe_put_home_actor_ids(streams)
  end

  defp maybe_subscribe_timeline(%{timeline_subscribed: true} = state, _streams), do: state

  defp maybe_subscribe_timeline(state, streams) do
    if Enum.any?(streams, &(&1 in StreamingStreams.timeline_streams())) do
      Timeline.subscribe()
      Map.put(state, :timeline_subscribed, true)
    else
      state
    end
  end

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

  defp maybe_unsubscribe_timeline(%{timeline_subscribed: false} = state, _streams), do: state

  defp maybe_unsubscribe_timeline(state, streams) do
    if Enum.any?(streams, &(&1 in StreamingStreams.timeline_streams())) do
      state
    else
      Phoenix.PubSub.unsubscribe(PleromaRedux.PubSub, "timeline")
      Map.put(state, :timeline_subscribed, false)
    end
  end

  defp maybe_unsubscribe_notifications(%{notifications_subscribed: false} = state, _streams),
    do: state

  defp maybe_unsubscribe_notifications(%{current_user: %User{} = user} = state, streams) do
    if Enum.any?(streams, &(&1 in StreamingStreams.notification_streams())) do
      state
    else
      Phoenix.PubSub.unsubscribe(PleromaRedux.PubSub, "notifications:" <> user.ap_id)
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
    if deliver_public_status?(object) do
      streams
      |> Enum.filter(fn
        "user" -> deliver_user_status?(object, state)
        "public" -> true
        "public:local" -> object.local
        _ -> false
      end)
    else
      []
    end
  end

  defp streams_for_notification(%{streams: %MapSet{} = streams}) do
    streams
    |> Enum.filter(&(&1 in StreamingStreams.notification_streams()))
  end

  defp deliver_public_status?(%Object{type: type}) when type in ~w(Note Announce), do: true
  defp deliver_public_status?(_object), do: false

  defp deliver_user_status?(%Object{type: type} = object, %{home_actor_ids: %MapSet{} = actor_ids})
       when type in ~w(Note Announce) do
    is_binary(object.actor) and MapSet.member?(actor_ids, object.actor)
  end

  defp deliver_user_status?(_object, _state), do: false

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
end
