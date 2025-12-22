defmodule PleromaReduxWeb.NodeinfoControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

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
    assert body["software"]["name"] == "pleroma_redux"
    assert "activitypub" in body["protocols"]
  end

  test "GET /nodeinfo/2.0 returns minimal payload", %{conn: conn} do
    conn = get(conn, "/nodeinfo/2.0")
    body = json_response(conn, 200)

    assert body["version"] == "2.0"
    assert body["software"]["name"] == "pleroma_redux"
    assert "activitypub" in body["protocols"]
  end
end
