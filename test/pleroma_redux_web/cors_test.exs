defmodule PleromaReduxWeb.CORSTest do
  use PleromaReduxWeb.ConnCase, async: true

  import Plug.Conn

  test "adds CORS headers for API responses", %{conn: conn} do
    conn =
      conn
      |> put_req_header("origin", "https://frontend.example")
      |> get("/api/v1/instance")

    assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
    assert [exposed] = get_resp_header(conn, "access-control-expose-headers")
    assert String.contains?(String.downcase(exposed), "link")
  end

  test "responds to API preflight requests", %{conn: conn} do
    conn =
      conn
      |> put_req_header("origin", "https://frontend.example")
      |> put_req_header("access-control-request-method", "GET")
      |> put_req_header("access-control-request-headers", "authorization,content-type")
      |> options("/api/v1/instance")

    assert conn.status == 204
    assert conn.resp_body == ""

    assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
    assert [methods] = get_resp_header(conn, "access-control-allow-methods")
    assert String.contains?(methods, "GET")
    assert get_resp_header(conn, "access-control-allow-headers") == ["authorization,content-type"]
  end

  test "does not add CORS headers for browser pages", %{conn: conn} do
    conn =
      conn
      |> put_req_header("origin", "https://frontend.example")
      |> get("/")

    assert get_resp_header(conn, "access-control-allow-origin") == []
  end
end

