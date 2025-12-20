defmodule PleromaReduxWeb.MastodonAPI.StreamingControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  alias PleromaRedux.Users

  defp with_websocket_headers(conn) do
    %Plug.Conn{} = conn

    conn = %{
      conn
      | host: "example.com",
        req_headers: [{"host", "example.com"} | conn.req_headers]
    }

    conn
    |> put_req_header("connection", "Upgrade")
    |> put_req_header("upgrade", "websocket")
    |> put_req_header("sec-websocket-key", Base.encode64(:crypto.strong_rand_bytes(16)))
    |> put_req_header("sec-websocket-version", "13")
  end

  test "GET /api/v1/streaming rejects unknown streams", %{conn: conn} do
    conn = get(conn, "/api/v1/streaming?stream=unknown")
    assert response(conn, 400)
  end

  test "GET /api/v1/streaming requires auth for user stream", %{conn: conn} do
    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:error, :unauthorized} end)

    conn = conn |> with_websocket_headers() |> get("/api/v1/streaming?stream=user")
    assert response(conn, 401)
  end

  test "GET /api/v1/streaming upgrades for public stream", %{conn: conn} do
    conn = conn |> with_websocket_headers() |> get("/api/v1/streaming?stream=public")
    assert conn.state == :upgraded
  end

  test "GET /api/v1/streaming upgrades for user stream when authorized", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    conn = conn |> with_websocket_headers() |> get("/api/v1/streaming?stream=user")
    assert conn.state == :upgraded
  end
end
