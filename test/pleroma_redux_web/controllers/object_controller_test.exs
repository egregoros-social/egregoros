defmodule PleromaReduxWeb.ObjectControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Users
  alias PleromaReduxWeb.Endpoint

  test "GET /objects/:uuid returns stored object as ActivityPub JSON", %{conn: conn} do
    {:ok, user} = Users.create_local_user("dana")
    uuid = Ecto.UUID.generate()

    note = %{
      "id" => Endpoint.url() <> "/objects/" <> uuid,
      "type" => "Note",
      "attributedTo" => user.ap_id,
      "content" => "Hello from objects endpoint"
    }

    assert {:ok, _} = Pipeline.ingest(note, local: true)

    conn = get(conn, "/objects/#{uuid}")
    assert conn.status == 200

    [content_type] = get_resp_header(conn, "content-type")
    assert String.contains?(content_type, "application/activity+json")

    decoded = Jason.decode!(conn.resp_body)
    assert decoded["@context"] == "https://www.w3.org/ns/activitystreams"
    assert decoded["id"] == note["id"]
    assert decoded["type"] == "Note"
    assert decoded["content"] == "Hello from objects endpoint"
  end

  test "GET /objects/:uuid returns 404 when missing", %{conn: conn} do
    uuid = Ecto.UUID.generate()
    conn = get(conn, "/objects/#{uuid}")
    assert response(conn, 404)
  end

  test "GET /objects/:uuid does not serve remote objects with local ids", %{conn: conn} do
    uuid = Ecto.UUID.generate()
    ap_id = Endpoint.url() <> "/objects/" <> uuid

    assert {:ok, _object} =
             Objects.create_object(%{
               ap_id: ap_id,
               type: "Note",
               actor: "https://remote.example/users/mallory",
               local: false,
               data: %{"id" => ap_id, "type" => "Note", "actor" => "https://remote.example/users/mallory"}
             })

    conn = get(conn, "/objects/#{uuid}")
    assert response(conn, 404)
  end
end
