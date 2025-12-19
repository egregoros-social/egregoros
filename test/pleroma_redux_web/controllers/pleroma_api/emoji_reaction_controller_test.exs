defmodule PleromaReduxWeb.PleromaAPI.EmojiReactionControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
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
end
