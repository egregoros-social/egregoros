defmodule PleromaReduxWeb.OutboxControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  alias PleromaRedux.Pipeline
  alias PleromaRedux.Users

  test "GET /users/:nickname/outbox returns ordered collection", %{conn: conn} do
    {:ok, user} = Users.create_local_user("ella")

    note = %{
      "id" => "https://example.com/objects/outbox-note",
      "type" => "Note",
      "attributedTo" => user.ap_id,
      "content" => "Outbox hello"
    }

    assert {:ok, _object} = Pipeline.ingest(note, local: true)

    conn = get(conn, "/users/ella/outbox")
    body = json_response(conn, 200)

    assert body["type"] == "OrderedCollection"
    assert Enum.any?(body["orderedItems"], &(&1["id"] == note["id"]))
  end
end
