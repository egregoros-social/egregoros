defmodule PleromaReduxWeb.MastodonAPI.StreamingSocketTest do
  use PleromaRedux.DataCase, async: true

  alias PleromaRedux.Object
  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Publish
  alias PleromaRedux.Users
  alias PleromaReduxWeb.MastodonAPI.StreamingSocket

  defp decode_frame({:text, payload}) do
    frame = Jason.decode!(payload)

    payload =
      case frame do
        %{"payload" => inner} when is_binary(inner) -> Jason.decode!(inner)
        _ -> nil
      end

    {frame, payload}
  end

  test "pushes an update event for public stream" do
    {:ok, bob} = Users.create_local_user("bob")
    {:ok, create} = Publish.post_note(bob, "Hello from Bob")

    %Object{} = note = Objects.get_by_ap_id(create.object)

    state = %{streams: ["public"], current_user: nil, home_actor_ids: MapSet.new()}

    assert {:push, frame, ^state} = StreamingSocket.handle_info({:post_created, note}, state)
    {outer, inner} = decode_frame(frame)

    assert outer["event"] == "update"
    assert is_binary(outer["payload"])
    assert inner["content"] == "<p>Hello from Bob</p>"
  end

  test "filters non-local objects from public:local stream" do
    remote_note = %Object{
      id: 123,
      ap_id: "https://remote.example/objects/123",
      type: "Note",
      actor: "https://remote.example/users/alice",
      object: nil,
      data: %{"content" => "<p>Remote</p>"},
      local: false
    }

    state = %{streams: ["public:local"], current_user: nil, home_actor_ids: MapSet.new()}

    assert {:ok, ^state} = StreamingSocket.handle_info({:post_created, remote_note}, state)
  end

  test "filters user stream updates to the home actor set" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")
    {:ok, charlie} = Users.create_local_user("charlie")

    {:ok, bob_create} = Publish.post_note(bob, "Hi from Bob")
    {:ok, charlie_create} = Publish.post_note(charlie, "Hi from Charlie")

    %Object{} = bob_note = Objects.get_by_ap_id(bob_create.object)
    %Object{} = charlie_note = Objects.get_by_ap_id(charlie_create.object)

    state = %{
      streams: ["user"],
      current_user: alice,
      home_actor_ids: MapSet.new([alice.ap_id, bob.ap_id])
    }

    assert {:push, frame, ^state} = StreamingSocket.handle_info({:post_created, bob_note}, state)
    {outer, inner} = decode_frame(frame)
    assert outer["event"] == "update"
    assert inner["content"] == "<p>Hi from Bob</p>"

    assert {:ok, ^state} = StreamingSocket.handle_info({:post_created, charlie_note}, state)
  end

  test "pushes a notification event for user stream" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    {:ok, _follow} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/activities/follow/1",
          "type" => "Follow",
          "actor" => bob.ap_id,
          "object" => alice.ap_id
        },
        local: true
      )

    [activity] = PleromaRedux.Notifications.list_for_user(alice, limit: 1)

    state = %{
      streams: ["user"],
      current_user: alice,
      home_actor_ids: MapSet.new([alice.ap_id])
    }

    assert {:push, frame, ^state} =
             StreamingSocket.handle_info({:notification_created, activity}, state)

    {outer, inner} = decode_frame(frame)
    assert outer["event"] == "notification"
    assert inner["type"] == "follow"
    assert inner["account"]["username"] == "bob"
    assert inner["status"] == nil
  end
end
