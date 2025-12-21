defmodule PleromaReduxWeb.MastodonAPI.NotificationRendererTest do
  use PleromaRedux.DataCase, async: true

  alias PleromaRedux.Objects
  alias PleromaRedux.Users
  alias PleromaReduxWeb.MastodonAPI.NotificationRenderer

  test "renders follow notifications without a status" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    {:ok, follow} =
      Objects.create_object(%{
        ap_id: "https://remote.example/activities/follow/1",
        type: "Follow",
        actor: bob.ap_id,
        object: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/activities/follow/1",
          "type" => "Follow",
          "actor" => bob.ap_id,
          "object" => alice.ap_id
        }
      })

    rendered = NotificationRenderer.render_notification(follow, alice)

    assert rendered["type"] == "follow"
    assert rendered["status"] == nil
    assert rendered["account"]["username"] == "bob"
  end

  test "renders favourite notifications with a rendered status" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    {:ok, note} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/1",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/1",
          "type" => "Note",
          "actor" => alice.ap_id,
          "content" => "<p>hello</p>"
        }
      })

    {:ok, like} =
      Objects.create_object(%{
        ap_id: "https://remote.example/activities/like/1",
        type: "Like",
        actor: bob.ap_id,
        object: note.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/activities/like/1",
          "type" => "Like",
          "actor" => bob.ap_id,
          "object" => note.ap_id
        }
      })

    rendered = NotificationRenderer.render_notification(like, alice)

    assert rendered["type"] == "favourite"
    assert %{"id" => note_id} = rendered["status"]
    assert note_id == Integer.to_string(note.id)
  end

  test "renders reblog notifications with a rendered status" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    {:ok, note} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/1",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/1",
          "type" => "Note",
          "actor" => alice.ap_id,
          "content" => "<p>hello</p>"
        }
      })

    {:ok, announce} =
      Objects.create_object(%{
        ap_id: "https://remote.example/activities/announce/1",
        type: "Announce",
        actor: bob.ap_id,
        object: note.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/activities/announce/1",
          "type" => "Announce",
          "actor" => bob.ap_id,
          "object" => note.ap_id
        }
      })

    rendered = NotificationRenderer.render_notification(announce, alice)

    assert rendered["type"] == "reblog"
    assert %{"id" => note_id} = rendered["status"]
    assert note_id == Integer.to_string(note.id)
  end

  test "renders unknown actors with a fallback acct" do
    {:ok, alice} = Users.create_local_user("alice")

    {:ok, follow} =
      Objects.create_object(%{
        ap_id: "https://remote.example/activities/follow/1",
        type: "Follow",
        actor: "https://remote.example/users/mallory",
        object: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/activities/follow/1",
          "type" => "Follow",
          "actor" => "https://remote.example/users/mallory",
          "object" => alice.ap_id
        }
      })

    rendered = NotificationRenderer.render_notification(follow, alice)

    assert rendered["account"]["id"] == "https://remote.example/users/mallory"
    assert rendered["account"]["acct"] == "mallory"
  end
end
