defmodule PleromaReduxWeb.InboxControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  alias PleromaRedux.Objects
  alias PleromaRedux.Users

  test "POST /users/:nickname/inbox ingests activity", %{conn: conn} do
    {:ok, _user} = Users.create_local_user("frank")

    note = %{
      "id" => "https://remote.example/objects/1",
      "type" => "Note",
      "attributedTo" => "https://remote.example/users/alice",
      "content" => "Hello from remote"
    }

    conn = post(conn, "/users/frank/inbox", note)
    assert response(conn, 202)

    assert Objects.get_by_ap_id(note["id"])
  end
end
