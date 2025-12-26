defmodule EgregorosWeb.MastodonAPI.StreamingControllerTest do
  use EgregorosWeb.ConnCase, async: true

  alias Egregoros.OAuth
  alias Egregoros.Users

  defp with_websocket_headers(conn, opts \\ []) do
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
    |> maybe_put_protocol_header(opts)
  end

  defp maybe_put_protocol_header(conn, opts) do
    case Keyword.fetch(opts, :protocol) do
      {:ok, protocol} when is_binary(protocol) ->
        put_req_header(conn, "sec-websocket-protocol", protocol)

      _ ->
        conn
    end
  end

  test "GET /api/v1/streaming rejects non-websocket requests", %{conn: conn} do
    conn = get(conn, "/api/v1/streaming")
    assert response(conn, 400) == "WebSocket upgrade required"
  end

  test "GET /api/v1/streaming rejects unknown streams", %{conn: conn} do
    conn = conn |> with_websocket_headers() |> get("/api/v1/streaming?stream=unknown")
    assert response(conn, 400) == "Unknown stream"
  end

  test "GET /api/v1/streaming upgrades without an initial stream", %{conn: conn} do
    conn = conn |> with_websocket_headers() |> get("/api/v1/streaming")
    assert conn.state == :upgraded
  end

  test "GET /api/v1/streaming treats blank streams as no initial streams", %{conn: conn} do
    conn = conn |> with_websocket_headers() |> get("/api/v1/streaming?stream=%20")
    assert conn.state == :upgraded
  end

  test "GET /api/v1/streaming requires auth for user stream", %{conn: conn} do
    conn = conn |> with_websocket_headers() |> get("/api/v1/streaming?stream=user")
    assert response(conn, 401) == "Unauthorized"
  end

  test "GET /api/v1/streaming upgrades for public stream", %{conn: conn} do
    conn = conn |> with_websocket_headers() |> get("/api/v1/streaming?stream=public")
    assert conn.state == :upgraded
  end

  test "GET /api/v1/streaming/public upgrades for public stream", %{conn: conn} do
    conn = conn |> with_websocket_headers() |> get("/api/v1/streaming/public")
    assert conn.state == :upgraded
  end

  test "GET /api/v1/streaming/public/local upgrades for public:local stream", %{conn: conn} do
    conn = conn |> with_websocket_headers() |> get("/api/v1/streaming/public/local")
    assert conn.state == :upgraded
  end

  test "GET /api/v1/streaming upgrades for a normalized stream list", %{conn: conn} do
    conn =
      conn
      |> with_websocket_headers()
      |> get("/api/v1/streaming?stream[]=public&stream[]=%20&stream[]=public")

    assert conn.state == :upgraded
  end

  test "GET /api/v1/streaming upgrades for user stream when authorized", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")

    {:ok, app} =
      OAuth.create_application(%{
        "client_name" => "Elk",
        "redirect_uris" => "urn:ietf:wg:oauth:2.0:oob",
        "scopes" => "read"
      })

    {:ok, auth_code} =
      OAuth.create_authorization_code(app, user, "urn:ietf:wg:oauth:2.0:oob", "read")

    {:ok, token} =
      OAuth.exchange_code_for_token(%{
        "grant_type" => "authorization_code",
        "code" => auth_code.code,
        "client_id" => app.client_id,
        "client_secret" => app.client_secret,
        "redirect_uri" => "urn:ietf:wg:oauth:2.0:oob"
      })

    conn =
      conn
      |> with_websocket_headers(protocol: token.token)
      |> get("/api/v1/streaming?stream=user")

    assert Plug.Conn.get_resp_header(conn, "sec-websocket-protocol") == [token.token]
    assert conn.state == :upgraded
  end
end
