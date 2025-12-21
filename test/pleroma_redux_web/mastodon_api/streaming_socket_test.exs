defmodule PleromaReduxWeb.MastodonAPI.StreamingSocketTest do
  use PleromaRedux.DataCase, async: true

  alias PleromaRedux.Activities.Note
  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Relationships
  alias PleromaRedux.Users
  alias PleromaReduxWeb.MastodonAPI.StreamingSocket

  test "init computes home_actor_ids for user streams" do
    {:ok, user} = Users.create_local_user("alice")
    {:ok, followed} = Users.create_user(remote_user_attrs("bob@example.com"))

    assert {:ok, _} =
             Relationships.upsert_relationship(%{
               type: "Follow",
               actor: user.ap_id,
               object: followed.ap_id,
               activity_ap_id: "https://example.com/activities/follow/1"
             })

    assert {:ok, state} = StreamingSocket.init(%{streams: ["user"], current_user: user})

    assert MapSet.member?(state.home_actor_ids, user.ap_id)
    assert MapSet.member?(state.home_actor_ids, followed.ap_id)
  end

  test "heartbeat pushes an event payload" do
    {:ok, state} = StreamingSocket.init(%{streams: [], current_user: nil})

    assert {:push, {:text, payload}, _state} = StreamingSocket.handle_info(:heartbeat, state)

    assert %{"event" => "heartbeat"} = Jason.decode!(payload)
  end

  test "delivers user timeline updates for followed actors" do
    {:ok, user} = Users.create_local_user("alice")
    {:ok, followed} = Users.create_user(remote_user_attrs("bob@example.com"))

    assert {:ok, _} =
             Relationships.upsert_relationship(%{
               type: "Follow",
               actor: user.ap_id,
               object: followed.ap_id,
               activity_ap_id: "https://example.com/activities/follow/1"
             })

    {:ok, state} = StreamingSocket.init(%{streams: ["user"], current_user: user})

    assert {:ok, note} =
             Objects.create_object(%{
               ap_id: "https://remote.example/objects/1",
               type: "Note",
               actor: followed.ap_id,
               local: false,
               data: %{
                 "id" => "https://remote.example/objects/1",
                 "type" => "Note",
                 "attributedTo" => followed.ap_id,
                 "content" => "<p>Hello</p>"
               }
             })

    assert {:push, {:text, payload}, ^state} =
             StreamingSocket.handle_info({:post_created, note}, state)

    assert %{"event" => "update", "payload" => status_payload} = Jason.decode!(payload)
    assert is_binary(status_payload)
    assert %{"id" => _id} = Jason.decode!(status_payload)
  end

  test "filters user streams when the actor is not in the home timeline set" do
    {:ok, user} = Users.create_local_user("alice")
    {:ok, state} = StreamingSocket.init(%{streams: ["user"], current_user: user})

    assert {:ok, note} =
             Objects.create_object(%{
               ap_id: "https://remote.example/objects/2",
               type: "Note",
               actor: "https://remote.example/users/stranger",
               local: false,
               data: %{
                 "id" => "https://remote.example/objects/2",
                 "type" => "Note",
                 "attributedTo" => "https://remote.example/users/stranger",
                 "content" => "<p>Hello</p>"
               }
             })

    assert {:ok, ^state} = StreamingSocket.handle_info({:post_created, note}, state)
  end

  test "delivers public timeline updates without a current user" do
    {:ok, state} = StreamingSocket.init(%{streams: ["public"], current_user: nil})

    assert {:ok, note} =
             Objects.create_object(%{
               ap_id: "https://remote.example/objects/3",
               type: "Note",
               actor: "https://remote.example/users/alice",
               local: false,
               data: %{
                 "id" => "https://remote.example/objects/3",
                 "type" => "Note",
                 "attributedTo" => "https://remote.example/users/alice",
                 "content" => "<p>Hello</p>"
               }
             })

    assert {:push, {:text, payload}, ^state} =
             StreamingSocket.handle_info({:post_created, note}, state)

    assert %{"event" => "update", "payload" => status_payload} = Jason.decode!(payload)
    assert is_binary(status_payload)
    assert %{"id" => _id} = Jason.decode!(status_payload)
  end

  test "delivers notifications for signed-in user streams" do
    {:ok, user} = Users.create_local_user("alice")

    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Hello"), local: true)

    {:ok, like_actor} = Users.create_user(remote_user_attrs("bob@example.com"))

    activity = %{
      "id" => "https://remote.example/activities/like/1",
      "type" => "Like",
      "actor" => like_actor.ap_id,
      "object" => note.ap_id
    }

    assert {:ok, like} = Pipeline.ingest(activity, local: false)

    {:ok, state} = StreamingSocket.init(%{streams: ["user"], current_user: user})

    assert {:push, {:text, payload}, ^state} =
             StreamingSocket.handle_info({:notification_created, like}, state)

    assert %{"event" => "notification", "payload" => notification_payload} =
             Jason.decode!(payload)

    assert is_binary(notification_payload)
    assert %{"id" => _id, "type" => _type} = Jason.decode!(notification_payload)
  end

  test "handle_in ignores incoming frames" do
    {:ok, state} = StreamingSocket.init(%{streams: [], current_user: nil})
    assert {:ok, ^state} = StreamingSocket.handle_in({"ping", opcode: :text}, state)
  end

  defp remote_user_attrs(handle) do
    [nickname, domain] = String.split(handle, "@", parts: 2)

    %{
      nickname: nickname,
      domain: domain,
      ap_id: "https://#{domain}/users/#{nickname}",
      inbox: "https://#{domain}/users/#{nickname}/inbox",
      outbox: "https://#{domain}/users/#{nickname}/outbox",
      public_key: "remote-key",
      private_key: nil,
      local: false
    }
  end
end

