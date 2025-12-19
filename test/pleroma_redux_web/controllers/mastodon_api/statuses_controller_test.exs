defmodule PleromaReduxWeb.MastodonAPI.StatusesControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Users
  alias PleromaReduxWeb.Endpoint

  test "POST /api/v1/statuses creates a status", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    conn = post(conn, "/api/v1/statuses", %{"status" => "Hello API"})

    response = json_response(conn, 200)
    assert response["content"] == "Hello API"
    assert response["account"]["username"] == "local"

    [object] = Objects.list_notes()
    assert object.data["content"] == "Hello API"
  end

  test "POST /api/v1/statuses rejects empty status", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    conn = post(conn, "/api/v1/statuses", %{"status" => "  "})
    assert response(conn, 422)
  end

  test "GET /api/v1/statuses/:id returns a status", %{conn: conn} do
    {:ok, _user} = Users.create_local_user("local")

    {:ok, _} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/objects/1",
          "type" => "Note",
          "actor" => "https://example.com/users/alice",
          "content" => "Hello show"
        },
        local: false
      )

    [object] = Objects.list_notes()

    conn = get(conn, "/api/v1/statuses/#{object.id}")

    response = json_response(conn, 200)
    assert response["id"] == Integer.to_string(object.id)
    assert response["content"] == "Hello show"
  end

  test "POST /api/v1/statuses/:id/favourite creates a like", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    {:ok, _} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/objects/2",
          "type" => "Note",
          "actor" => "https://example.com/users/alice",
          "content" => "Hello like"
        },
        local: false
      )

    [object] = Objects.list_notes()

    conn = post(conn, "/api/v1/statuses/#{object.id}/favourite")
    response = json_response(conn, 200)
    assert response["account"]["username"] == "alice"

    assert Objects.get_by_type_actor_object("Like", user.ap_id, object.ap_id)
  end

  test "POST /api/v1/statuses/:id/unfavourite creates an undo", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    {:ok, note} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/objects/3",
          "type" => "Note",
          "actor" => "https://example.com/users/alice",
          "content" => "Hello unlike"
        },
        local: false
      )

    like =
      %{
        "id" => "https://example.com/activities/like/1",
        "type" => "Like",
        "actor" => user.ap_id,
        "object" => note.ap_id
      }

    {:ok, like_object} = Pipeline.ingest(like, local: true)

    conn = post(conn, "/api/v1/statuses/#{note.id}/unfavourite")
    assert json_response(conn, 200)

    assert Objects.get_by_type_actor_object("Undo", user.ap_id, like_object.ap_id)
  end

  test "POST /api/v1/statuses/:id/reblog creates an announce", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    {:ok, note} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/objects/4",
          "type" => "Note",
          "actor" => "https://example.com/users/alice",
          "content" => "Hello reblog"
        },
        local: false
      )

    conn = post(conn, "/api/v1/statuses/#{note.id}/reblog")
    assert json_response(conn, 200)

    assert Objects.get_by_type_actor_object("Announce", user.ap_id, note.ap_id)
  end

  test "POST /api/v1/statuses/:id/unreblog creates an undo", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    {:ok, note} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/objects/5",
          "type" => "Note",
          "actor" => "https://example.com/users/alice",
          "content" => "Hello unreblog"
        },
        local: false
      )

    announce =
      %{
        "id" => "https://example.com/activities/announce/1",
        "type" => "Announce",
        "actor" => user.ap_id,
        "object" => note.ap_id
      }

    {:ok, announce_object} = Pipeline.ingest(announce, local: true)

    conn = post(conn, "/api/v1/statuses/#{note.id}/unreblog")
    assert json_response(conn, 200)

    assert Objects.get_by_type_actor_object("Undo", user.ap_id, announce_object.ap_id)
  end

  test "POST /api/v1/statuses/:id/favourite is idempotent", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, 2, fn _conn -> {:ok, user} end)

    {:ok, note} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/objects/like-idempotent",
          "type" => "Note",
          "actor" => "https://example.com/users/alice",
          "content" => "Hello like"
        },
        local: false
      )

    conn = post(conn, "/api/v1/statuses/#{note.id}/favourite")
    assert json_response(conn, 200)

    conn = post(conn, "/api/v1/statuses/#{note.id}/favourite")
    assert json_response(conn, 200)

    assert Objects.count_by_type_object("Like", note.ap_id) == 1
  end

  test "POST /api/v1/statuses/:id/reblog is idempotent", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, 2, fn _conn -> {:ok, user} end)

    {:ok, note} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/objects/reblog-idempotent",
          "type" => "Note",
          "actor" => "https://example.com/users/alice",
          "content" => "Hello reblog"
        },
        local: false
      )

    conn = post(conn, "/api/v1/statuses/#{note.id}/reblog")
    assert json_response(conn, 200)

    conn = post(conn, "/api/v1/statuses/#{note.id}/reblog")
    assert json_response(conn, 200)

    assert Objects.count_by_type_object("Announce", note.ap_id) == 1
  end

  test "POST /api/v1/statuses accepts media_ids and attaches media", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    ap_id = Endpoint.url() <> "/objects/" <> Ecto.UUID.generate()

    {:ok, media} =
      Objects.create_object(%{
        ap_id: ap_id,
        type: "Image",
        actor: user.ap_id,
        local: true,
        published: DateTime.utc_now(),
        data: %{
          "id" => ap_id,
          "type" => "Image",
          "mediaType" => "image/png",
          "url" => [
            %{
              "type" => "Link",
              "mediaType" => "image/png",
              "href" => Endpoint.url() <> "/uploads/media/#{user.id}/image.png"
            }
          ],
          "name" => ""
        }
      })

    conn =
      post(conn, "/api/v1/statuses", %{
        "status" => "Hello with media",
        "media_ids" => [Integer.to_string(media.id)]
      })

    response = json_response(conn, 200)

    assert response["content"] == "Hello with media"
    assert length(response["media_attachments"]) == 1

    attachment = Enum.at(response["media_attachments"], 0)
    assert attachment["id"] == Integer.to_string(media.id)
    assert attachment["type"] == "image"
    assert String.ends_with?(attachment["url"], "/uploads/media/#{user.id}/image.png")

    [note] = Objects.list_notes()
    assert is_list(note.data["attachment"])
    assert Enum.at(note.data["attachment"], 0)["type"] == "Image"
  end

  test "POST /api/v1/statuses rejects media_ids not owned by the user", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")
    {:ok, other} = Users.create_local_user("other")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    ap_id = Endpoint.url() <> "/objects/" <> Ecto.UUID.generate()

    {:ok, media} =
      Objects.create_object(%{
        ap_id: ap_id,
        type: "Image",
        actor: other.ap_id,
        local: true,
        published: DateTime.utc_now(),
        data: %{
          "id" => ap_id,
          "type" => "Image",
          "mediaType" => "image/png",
          "url" => [
            %{
              "type" => "Link",
              "mediaType" => "image/png",
              "href" => Endpoint.url() <> "/uploads/media/#{other.id}/image.png"
            }
          ],
          "name" => ""
        }
      })

    conn =
      post(conn, "/api/v1/statuses", %{
        "status" => "Hello with media",
        "media_ids" => [Integer.to_string(media.id)]
      })

    assert response(conn, 422)
  end

  test "POST /api/v1/statuses attaches uploaded media from /api/v1/media", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, 2, fn _conn -> {:ok, user} end)

    PleromaRedux.MediaStorage.Mock
    |> expect(:store_media, fn ^user, %Plug.Upload{filename: "image.png"} ->
      {:ok, "/uploads/media/#{user.id}/image.png"}
    end)

    upload =
      %Plug.Upload{
        path: tmp_upload_path(),
        filename: "image.png",
        content_type: "image/png"
      }

    conn = post(conn, "/api/v1/media", %{"file" => upload})
    media = json_response(conn, 200)

    conn =
      build_conn()
      |> post("/api/v1/statuses", %{
        "status" => "Hello with uploaded media",
        "media_ids" => [media["id"]]
      })

    response = json_response(conn, 200)

    assert response["content"] == "Hello with uploaded media"
    assert length(response["media_attachments"]) == 1
    assert Enum.at(response["media_attachments"], 0)["id"] == media["id"]
  end

  test "GET /api/v1/statuses/:id/context returns empty context", %{conn: conn} do
    {:ok, _user} = Users.create_local_user("local")

    {:ok, note} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/objects/ctx-1",
          "type" => "Note",
          "actor" => "https://example.com/users/alice",
          "content" => "Hello context"
        },
        local: false
      )

    conn = get(conn, "/api/v1/statuses/#{note.id}/context")
    response = json_response(conn, 200)

    assert response["ancestors"] == []
    assert response["descendants"] == []
  end

  defp tmp_upload_path do
    path = Path.join(System.tmp_dir!(), "pleroma-redux-test-upload-#{Ecto.UUID.generate()}")
    File.write!(path, <<0, 1, 2, 3>>)
    path
  end
end
