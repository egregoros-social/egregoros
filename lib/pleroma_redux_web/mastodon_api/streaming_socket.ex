defmodule PleromaReduxWeb.MastodonAPI.StreamingSocket do
  @behaviour WebSock

  alias PleromaRedux.Notifications
  alias PleromaRedux.Object
  alias PleromaRedux.Relationships
  alias PleromaRedux.Timeline
  alias PleromaRedux.User
  alias PleromaReduxWeb.MastodonAPI.NotificationRenderer
  alias PleromaReduxWeb.MastodonAPI.StatusRenderer

  @heartbeat_interval_ms 30_000

  @impl true
  def init(%{streams: streams, current_user: current_user} = state) when is_list(streams) do
    user_stream? = Enum.member?(streams, "user")
    public_stream? = Enum.member?(streams, "public")
    public_local_stream? = Enum.member?(streams, "public:local")

    if public_stream? or public_local_stream? or user_stream? do
      Timeline.subscribe()
    end

    home_actor_ids =
      case current_user do
        %User{} = user when user_stream? ->
          Notifications.subscribe(user.ap_id)
          home_actor_ids(user)

        _ ->
          MapSet.new()
      end

    state =
      state
      |> Map.put(:home_actor_ids, home_actor_ids)
      |> schedule_heartbeat()

    {:ok, state}
  end

  @impl true
  def handle_in({_payload, opcode: _opcode}, state) do
    {:ok, state}
  end

  @impl true
  def handle_info(:heartbeat, state) do
    {:push, {:text, encode_event("heartbeat")}, schedule_heartbeat(state)}
  end

  @impl true
  def handle_info({:post_created, %Object{} = object}, state) do
    if deliver_status?(object, state) do
      status_json =
        case Map.get(state, :current_user) do
          %User{} = user -> StatusRenderer.render_status(object, user)
          _ -> StatusRenderer.render_status(object)
        end
        |> Jason.encode!()

      {:push, {:text, encode_event("update", status_json)}, state}
    else
      {:ok, state}
    end
  end

  def handle_info(
        {:notification_created, %Object{} = activity},
        %{current_user: %User{} = user} = state
      ) do
    notification_json =
      activity
      |> NotificationRenderer.render_notification(user)
      |> Jason.encode!()

    {:push, {:text, encode_event("notification", notification_json)}, state}
  end

  def handle_info(_message, state) do
    {:ok, state}
  end

  defp deliver_status?(%Object{} = object, %{streams: streams} = state) do
    cond do
      "user" in streams and deliver_user_status?(object, state) ->
        true

      "public:local" in streams and deliver_public_status?(object) and object.local ->
        true

      "public" in streams and deliver_public_status?(object) ->
        true

      true ->
        false
    end
  end

  defp deliver_public_status?(%Object{type: type}) when type in ~w(Note Announce), do: true
  defp deliver_public_status?(_object), do: false

  defp deliver_user_status?(%Object{type: type} = object, %{home_actor_ids: %MapSet{} = actor_ids})
       when type in ~w(Note Announce) do
    is_binary(object.actor) and MapSet.member?(actor_ids, object.actor)
  end

  defp deliver_user_status?(_object, _state), do: false

  defp encode_event(event) when is_binary(event) do
    Jason.encode!(%{"event" => event})
  end

  defp encode_event(event, payload) when is_binary(event) and is_binary(payload) do
    Jason.encode!(%{"event" => event, "payload" => payload})
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
