defmodule PleromaReduxWeb.MastodonAPI.AccountsControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  alias PleromaRedux.Publish
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Relationships
  alias PleromaRedux.Users

  test "GET /api/v1/accounts/verify_credentials returns current user", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    conn = get(conn, "/api/v1/accounts/verify_credentials")
    response = json_response(conn, 200)

    assert response["id"] == Integer.to_string(user.id)
    assert response["username"] == "local"
  end

  test "GET /api/v1/accounts/:id returns account", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")

    conn = get(conn, "/api/v1/accounts/#{user.id}")
    response = json_response(conn, 200)

    assert response["id"] == Integer.to_string(user.id)
    assert response["username"] == "alice"
  end

  test "GET /api/v1/accounts/:id/statuses returns account statuses", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")

    {:ok, _} = Publish.post_note(user, "First post")
    {:ok, _} = Publish.post_note(user, "Second post")

    conn = get(conn, "/api/v1/accounts/#{user.id}/statuses")
    response = json_response(conn, 200)

    assert length(response) == 2
    assert Enum.at(response, 0)["content"] == "Second post"
    assert Enum.at(response, 1)["content"] == "First post"
  end

  test "POST /api/v1/accounts/:id/follow creates follow activity", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")
    {:ok, target} = Users.create_local_user("bob")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    conn = post(conn, "/api/v1/accounts/#{target.id}/follow")
    response = json_response(conn, 200)

    assert response["id"] == Integer.to_string(target.id)
    assert response["following"] == true

    assert PleromaRedux.Objects.get_by_type_actor_object("Follow", user.ap_id, target.ap_id)
  end

  test "POST /api/v1/accounts/:id/unfollow creates undo activity", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")
    {:ok, target} = Users.create_local_user("charlie")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    {:ok, follow} =
      PleromaRedux.Pipeline.ingest(
        %{
          "id" => "https://example.com/activities/follow/1",
          "type" => "Follow",
          "actor" => user.ap_id,
          "object" => target.ap_id
        },
        local: true
      )

    conn = post(conn, "/api/v1/accounts/#{target.id}/unfollow")
    response = json_response(conn, 200)
    assert response["id"] == Integer.to_string(target.id)
    assert response["following"] == false

    assert PleromaRedux.Objects.get_by_type_actor_object("Undo", user.ap_id, follow.ap_id)
  end

  test "POST /api/v1/accounts/:id/unfollow undoes the latest follow relationship", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")
    {:ok, target} = Users.create_local_user("dana")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    {:ok, follow_1} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/activities/follow/old",
          "type" => "Follow",
          "actor" => user.ap_id,
          "object" => target.ap_id
        },
        local: true
      )

    {:ok, follow_2} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/activities/follow/new",
          "type" => "Follow",
          "actor" => user.ap_id,
          "object" => target.ap_id
        },
        local: true
      )

    assert %{} = Relationships.get_by_type_actor_object("Follow", user.ap_id, target.ap_id)

    conn = post(conn, "/api/v1/accounts/#{target.id}/unfollow")
    response = json_response(conn, 200)
    assert response["following"] == false

    assert PleromaRedux.Objects.get_by_type_actor_object("Undo", user.ap_id, follow_2.ap_id)
    refute PleromaRedux.Objects.get_by_type_actor_object("Undo", user.ap_id, follow_1.ap_id)
    assert Relationships.get_by_type_actor_object("Follow", user.ap_id, target.ap_id) == nil
  end

  test "GET /api/v1/accounts/relationships returns relationship objects", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")
    {:ok, target_1} = Users.create_local_user("alice")
    {:ok, target_2} = Users.create_local_user("bob")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    conn = get(conn, "/api/v1/accounts/relationships", %{"id" => [target_1.id, target_2.id]})
    response = json_response(conn, 200)

    assert Enum.any?(response, &(&1["id"] == Integer.to_string(target_1.id)))
    assert Enum.any?(response, &(&1["id"] == Integer.to_string(target_2.id)))
  end
end
