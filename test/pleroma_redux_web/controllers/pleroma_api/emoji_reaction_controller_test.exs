defmodule PleromaReduxWeb.PleromaAPI.EmojiReactionControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Relationships
  alias PleromaRedux.Users

  test "PUT /api/v1/pleroma/statuses/:id/reactions/:emoji creates emoji reaction", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    {:ok, note} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/objects/emoji-1",
          "type" => "Note",
          "actor" => "https://example.com/users/alice",
          "content" => "Emoji reaction target"
        },
        local: false
      )

    conn = put(conn, "/api/v1/pleroma/statuses/#{note.id}/reactions/🔥")
    assert response(conn, 200)

    reaction =
      Objects.get_emoji_react(user.ap_id, note.ap_id, "🔥")

    assert reaction
    assert reaction.type == "EmojiReact"
    assert reaction.data["content"] == "🔥"
  end

  test "PUT /api/v1/pleroma/statuses/:id/reactions/:emoji is idempotent", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, 2, fn _conn -> {:ok, user} end)

    {:ok, note} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/objects/emoji-idempotent",
          "type" => "Note",
          "actor" => "https://example.com/users/alice",
          "content" => "Emoji reaction target"
        },
        local: false
      )

    conn = put(conn, "/api/v1/pleroma/statuses/#{note.id}/reactions/🔥")
    assert response(conn, 200)

    conn = put(conn, "/api/v1/pleroma/statuses/#{note.id}/reactions/🔥")
    assert response(conn, 200)

    assert %{} =
             Relationships.get_by_type_actor_object(
               "EmojiReact:🔥",
               user.ap_id,
               note.ap_id
             )

    assert Objects.count_by_type_object("EmojiReact", note.ap_id) == 1
  end

  test "DELETE /api/v1/pleroma/statuses/:id/reactions/:emoji creates undo", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    {:ok, note} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/objects/emoji-2",
          "type" => "Note",
          "actor" => "https://example.com/users/alice",
          "content" => "Emoji reaction target"
        },
        local: false
      )

    {:ok, reaction} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/activities/react/1",
          "type" => "EmojiReact",
          "actor" => user.ap_id,
          "object" => note.ap_id,
          "content" => "🔥"
        },
        local: true
      )

    conn = delete(conn, "/api/v1/pleroma/statuses/#{note.id}/reactions/🔥")
    assert response(conn, 200)

    assert Objects.get_by_type_actor_object("Undo", user.ap_id, reaction.ap_id)
  end

  test "GET /api/v1/pleroma/statuses/:id/reactions lists emoji reactions", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")
    {:ok, other_user} = Users.create_local_user("bob")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    {:ok, note} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/objects/emoji-3",
          "type" => "Note",
          "actor" => "https://example.com/users/alice",
          "content" => "Emoji reaction target"
        },
        local: false
      )

    assert {:ok, _} =
             Pipeline.ingest(
               %{
                 "id" => "https://example.com/activities/react/user",
                 "type" => "EmojiReact",
                 "actor" => user.ap_id,
                 "object" => note.ap_id,
                 "content" => "🔥"
               },
               local: true
             )

    assert {:ok, _} =
             Pipeline.ingest(
               %{
                 "id" => "https://example.com/activities/react/other",
                 "type" => "EmojiReact",
                 "actor" => other_user.ap_id,
                 "object" => note.ap_id,
                 "content" => "🔥"
               },
               local: true
             )

    conn = get(conn, "/api/v1/pleroma/statuses/#{note.id}/reactions")
    response = json_response(conn, 200)

    assert %{"name" => "🔥", "count" => 2, "me" => true} in response
  end
end
