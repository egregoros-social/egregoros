defmodule EgregorosWeb.CORSTest do
  use EgregorosWeb.ConnCase, async: true

  import Plug.Conn

  alias Egregoros.Objects
  alias EgregorosWeb.Endpoint

  @as_public "https://www.w3.org/ns/activitystreams#Public"

  test "adds CORS headers for API responses", %{conn: conn} do
    conn =
      conn
      |> put_req_header("origin", "https://frontend.example")
      |> get("/api/v1/instance")

    assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
    assert [exposed] = get_resp_header(conn, "access-control-expose-headers")
    assert String.contains?(String.downcase(exposed), "link")
  end

  test "adds CORS headers for nodeinfo responses", %{conn: conn} do
    conn =
      conn
      |> put_req_header("origin", "https://frontend.example")
      |> get("/nodeinfo/2.0")

    assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
  end

  test "responds to nodeinfo preflight requests", %{conn: conn} do
    conn =
      conn
      |> put_req_header("origin", "https://frontend.example")
      |> put_req_header("access-control-request-method", "GET")
      |> put_req_header("access-control-request-headers", "accept")
      |> options("/nodeinfo/2.0")

    assert conn.status == 204
    assert conn.resp_body == ""
    assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
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

  test "adds CORS headers for uploads responses", %{conn: conn} do
    conn =
      conn
      |> put_req_header("origin", "https://frontend.example")
      |> get("/uploads/media/1/does-not-exist.mp3")

    assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
  end

  test "responds to uploads preflight requests", %{conn: conn} do
    conn =
      conn
      |> put_req_header("origin", "https://frontend.example")
      |> put_req_header("access-control-request-method", "GET")
      |> put_req_header("access-control-request-headers", "range")
      |> options("/uploads/media/1/does-not-exist.mp3")

    assert conn.status == 204
    assert conn.resp_body == ""
    assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
    assert get_resp_header(conn, "access-control-allow-headers") == ["range"]
  end

  test "adds CORS headers for object responses", %{conn: conn} do
    uuid = Ecto.UUID.generate()
    ap_id = Endpoint.url() <> "/objects/" <> uuid
    _object = insert_public_object(ap_id, "Note")

    conn =
      conn
      |> put_req_header("origin", "https://frontend.example")
      |> get("/objects/" <> uuid)

    assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
  end

  test "adds CORS headers for activity responses", %{conn: conn} do
    uuid = Ecto.UUID.generate()
    ap_id = Endpoint.url() <> "/activities/" <> uuid
    _object = insert_public_object(ap_id, "Create")

    conn =
      conn
      |> put_req_header("origin", "https://frontend.example")
      |> get("/activities/" <> uuid)

    assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
  end

  test "does not add CORS headers for browser pages", %{conn: conn} do
    conn =
      conn
      |> put_req_header("origin", "https://frontend.example")
      |> get("/")

    assert get_resp_header(conn, "access-control-allow-origin") == []
  end

  defp insert_public_object(ap_id, type) when is_binary(ap_id) and is_binary(type) do
    data = %{"id" => ap_id, "type" => type, "to" => [@as_public]}
    {:ok, object} = Objects.create_object(%{ap_id: ap_id, type: type, data: data, local: true})
    object
  end
end
