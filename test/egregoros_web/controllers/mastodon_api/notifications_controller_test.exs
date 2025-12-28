defmodule EgregorosWeb.MastodonAPI.NotificationsControllerTest do
  use EgregorosWeb.ConnCase, async: true

  alias Egregoros.Activities.EmojiReact
  alias Egregoros.Publish
  alias Egregoros.Pipeline
  alias Egregoros.Users

  test "GET /api/v1/notifications returns a list", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    conn = get(conn, "/api/v1/notifications")
    response = json_response(conn, 200)

    assert is_list(response)
  end

  test "GET /api/v1/notifications includes follow and favourite notifications", %{conn: conn} do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    Egregoros.Auth.Mock
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
    assert Enum.at(response, 0)["status"]["content"] == "<p>Hello</p>"

    assert Enum.at(response, 1)["type"] == "follow"
    assert Enum.at(response, 1)["account"]["username"] == "bob"
    assert Enum.at(response, 1)["status"] == nil
  end

  test "GET /api/v1/notifications includes mention notifications and omits emoji reactions", %{
    conn: conn
  } do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, alice} end)

    {:ok, create} = Publish.post_note(alice, "Hello")

    assert {:ok, _} =
             Pipeline.ingest(
               EmojiReact.build(bob, create.object, "🔥"),
               local: true
             )

    {:ok, mention_create} = Publish.post_note(bob, "@alice Hello there")

    conn = get(conn, "/api/v1/notifications")
    response = json_response(conn, 200)

    assert Enum.any?(response, fn notification ->
             notification["type"] == "mention" and
               notification["account"]["username"] == "bob" and
               is_map(notification["status"]) and
               String.contains?(notification["status"]["content"], "Hello there") and
               notification["status"]["uri"] == mention_create.object
           end)

    refute Enum.any?(response, fn notification ->
             notification["type"] == "emojireact" or
               notification["type"] == "emoji_react" or
               notification["type"] == "emoji_reaction"
           end)

    assert Enum.any?(response, fn notification ->
             notification["type"] == "mention" and is_map(notification["status"])
           end)
  end
end
