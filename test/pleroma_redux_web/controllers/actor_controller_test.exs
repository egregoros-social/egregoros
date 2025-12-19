defmodule PleromaReduxWeb.ActorControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  alias PleromaRedux.Users

  test "GET /users/:nickname returns ActivityPub actor", %{conn: conn} do
    {:ok, user} = Users.create_local_user("dana")

    conn = get(conn, "/users/dana")
    assert json_response(conn, 200)["id"] == user.ap_id
    assert json_response(conn, 200)["preferredUsername"] == "dana"
    assert json_response(conn, 200)["publicKey"]["publicKeyPem"] == user.public_key
  end
end
