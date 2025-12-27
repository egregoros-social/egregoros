defmodule EgregorosWeb.NodeinfoControllerTest do
  use EgregorosWeb.ConnCase, async: true

  alias Egregoros.Publish
  alias Egregoros.Users

  test "GET /.well-known/nodeinfo returns links", %{conn: conn} do
    conn = get(conn, "/.well-known/nodeinfo")
    body = json_response(conn, 200)

    assert is_list(body["links"])
    assert Enum.any?(body["links"], &(&1["rel"] =~ "nodeinfo"))
  end

  test "GET /nodeinfo/2.0.json returns minimal payload", %{conn: conn} do
    conn = get(conn, "/nodeinfo/2.0.json")
    body = json_response(conn, 200)

    assert body["version"] == "2.0"
    assert body["software"]["name"] == "egregoros"
    assert "activitypub" in body["protocols"]
  end

  test "nodeinfo reports registrations and basic usage counts", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")
    {:ok, _note} = Publish.post_note(user, "hello", visibility: "public")

    conn = get(conn, "/nodeinfo/2.0.json")
    body = json_response(conn, 200)

    assert body["openRegistrations"] == true
    assert body["usage"]["users"]["total"] == 1
    assert body["usage"]["localPosts"] == 1
  end

  test "GET /nodeinfo/2.0 returns minimal payload", %{conn: conn} do
    conn = get(conn, "/nodeinfo/2.0")
    body = json_response(conn, 200)

    assert body["version"] == "2.0"
    assert body["software"]["name"] == "egregoros"
    assert "activitypub" in body["protocols"]
  end
end
