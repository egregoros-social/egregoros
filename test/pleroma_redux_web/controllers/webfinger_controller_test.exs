defmodule PleromaReduxWeb.WebFingerControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  alias PleromaRedux.Users
  alias PleromaReduxWeb.Endpoint

  test "GET /.well-known/webfinger returns local user", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")

    host = Endpoint.url() |> URI.parse() |> Map.fetch!(:host)
    resource = "acct:#{user.nickname}@#{host}"

    conn = get(conn, "/.well-known/webfinger", resource: resource)
    body = json_response(conn, 200)

    assert body["subject"] == resource

    self_link =
      Enum.find(body["links"], fn link ->
        link["rel"] == "self" and link["type"] == "application/activity+json"
      end)

    assert self_link["href"] == user.ap_id
  end
end
