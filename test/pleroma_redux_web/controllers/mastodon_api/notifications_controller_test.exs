defmodule PleromaReduxWeb.MastodonAPI.NotificationsControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  alias PleromaRedux.Publish
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Users

  test "GET /api/v1/notifications returns a list", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    conn = get(conn, "/api/v1/notifications")
    response = json_response(conn, 200)

    assert is_list(response)
  end

  test "GET /api/v1/notifications includes follow and favourite notifications", %{conn: conn} do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, alice} end)

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

    {:ok, create} = Publish.post_note(alice, "Hello")

    {:ok, _like} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/activities/like/1",
          "type" => "Like",
          "actor" => bob.ap_id,
          "object" => create.object
        },
        local: true
      )

    conn = get(conn, "/api/v1/notifications")
    response = json_response(conn, 200)

    assert is_list(response)
    assert length(response) == 2

    assert Enum.at(response, 0)["type"] == "favourite"
    assert Enum.at(response, 0)["account"]["username"] == "bob"
    assert Enum.at(response, 0)["status"]["content"] == "Hello"

    assert Enum.at(response, 1)["type"] == "follow"
    assert Enum.at(response, 1)["account"]["username"] == "bob"
    assert Enum.at(response, 1)["status"] == nil
  end
end
