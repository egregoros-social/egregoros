defmodule PleromaReduxWeb.InboxControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  alias PleromaRedux.Objects
  alias PleromaRedux.Users

  test "POST /users/:nickname/inbox ingests activity", %{conn: conn} do
    {:ok, _user} = Users.create_local_user("frank")
    {public_key, private_key} = PleromaRedux.Keys.generate_rsa_keypair()
    {:ok, _} =
      Users.create_user(%{
        nickname: "alice",
        ap_id: "https://remote.example/users/alice",
        inbox: "https://remote.example/users/alice/inbox",
        outbox: "https://remote.example/users/alice/outbox",
        public_key: public_key,
        private_key: private_key,
        local: false
      })

    note = %{
      "id" => "https://remote.example/objects/1",
      "type" => "Note",
      "attributedTo" => "https://remote.example/users/alice",
      "content" => "Hello from remote"
    }

    conn =
      conn
      |> sign_request("post", "/users/frank/inbox", private_key, "https://remote.example/users/alice#main-key")
      |> post("/users/frank/inbox", note)

    assert response(conn, 202)

    assert Objects.get_by_ap_id(note["id"])
  end

  test "POST /users/:nickname/inbox accepts signature with digest and host", %{conn: conn} do
    {:ok, _user} = Users.create_local_user("frank")
    {public_key, private_key} = PleromaRedux.Keys.generate_rsa_keypair()

    {:ok, _} =
      Users.create_user(%{
        nickname: "alice",
        ap_id: "https://remote.example/users/alice",
        inbox: "https://remote.example/users/alice/inbox",
        outbox: "https://remote.example/users/alice/outbox",
        public_key: public_key,
        private_key: private_key,
        local: false
      })

    note = %{
      "id" => "https://remote.example/objects/1-digest",
      "type" => "Note",
      "attributedTo" => "https://remote.example/users/alice",
      "content" => "Hello with digest"
    }

    body = Jason.encode!(note)
    headers = ["(request-target)", "host", "date", "digest", "content-length"]

    conn =
      conn
      |> put_req_header("content-type", "application/activity+json")
      |> put_req_header("accept", "application/activity+json")
      |> sign_request(
        "post",
        "/users/frank/inbox",
        private_key,
        "https://remote.example/users/alice#main-key",
        headers,
        body
      )
      |> post("/users/frank/inbox", body)

    assert response(conn, 202)
    assert Objects.get_by_ap_id(note["id"])
  end

  test "POST /users/:nickname/inbox rejects mismatched digest", %{conn: conn} do
    {:ok, _user} = Users.create_local_user("frank")
    {public_key, private_key} = PleromaRedux.Keys.generate_rsa_keypair()

    {:ok, _} =
      Users.create_user(%{
        nickname: "alice",
        ap_id: "https://remote.example/users/alice",
        inbox: "https://remote.example/users/alice/inbox",
        outbox: "https://remote.example/users/alice/outbox",
        public_key: public_key,
        private_key: private_key,
        local: false
      })

    note = %{
      "id" => "https://remote.example/objects/1-digest-mismatch",
      "type" => "Note",
      "attributedTo" => "https://remote.example/users/alice",
      "content" => "Original content"
    }

    tampered = Map.put(note, "content", "Tampered content")
    signed_body = Jason.encode!(note)
    sent_body = Jason.encode!(tampered)

    headers = ["(request-target)", "host", "date", "digest", "content-length"]

    conn =
      conn
      |> put_req_header("content-type", "application/activity+json")
      |> put_req_header("accept", "application/activity+json")
      |> sign_request(
        "post",
        "/users/frank/inbox",
        private_key,
        "https://remote.example/users/alice#main-key",
        headers,
        signed_body
      )
      |> post("/users/frank/inbox", sent_body)

    assert response(conn, 401)
    refute Objects.get_by_ap_id(note["id"])
  end

  test "POST /users/:nickname/inbox rejects old date signature", %{conn: conn} do
    {:ok, _user} = Users.create_local_user("frank")
    {public_key, private_key} = PleromaRedux.Keys.generate_rsa_keypair()

    {:ok, _} =
      Users.create_user(%{
        nickname: "alice",
        ap_id: "https://remote.example/users/alice",
        inbox: "https://remote.example/users/alice/inbox",
        outbox: "https://remote.example/users/alice/outbox",
        public_key: public_key,
        private_key: private_key,
        local: false
      })

    note = %{
      "id" => "https://remote.example/objects/1-old-date",
      "type" => "Note",
      "attributedTo" => "https://remote.example/users/alice",
      "content" => "Old date note"
    }

    old_date = DateTime.utc_now() |> DateTime.add(-400, :second) |> date_header()

    conn =
      conn
      |> put_req_header("date", old_date)
      |> sign_request("post", "/users/frank/inbox", private_key, "https://remote.example/users/alice#main-key")
      |> post("/users/frank/inbox", note)

    assert response(conn, 401)
    refute Objects.get_by_ap_id(note["id"])
  end

  test "POST /users/:nickname/inbox rejects invalid signature", %{conn: conn} do
    {:ok, _user} = Users.create_local_user("frank")

    note = %{
      "id" => "https://remote.example/objects/2",
      "type" => "Note",
      "attributedTo" => "https://remote.example/users/alice",
      "content" => "Hello from remote"
    }

    conn = post(conn, "/users/frank/inbox", note)
    assert response(conn, 401)

    refute Objects.get_by_ap_id(note["id"])
  end

  defp sign_request(
         conn,
         method,
         path,
         private_key_pem,
         key_id,
         headers \\ ["(request-target)", "date"],
         body \\ nil
       ) do
    headers = Enum.map(headers, &String.downcase/1)
    body = body || ""
    date = Plug.Conn.get_req_header(conn, "date") |> List.first() || date_header()
    host = host_header(conn)
    content_length = Integer.to_string(byte_size(body))
    digest = digest_header(body)

    conn =
      conn
      |> maybe_put_header(headers, "date", date)
      |> maybe_put_header(headers, "host", host)
      |> maybe_put_header(headers, "content-length", content_length)
      |> maybe_put_header(headers, "digest", digest)

    signature_string = signature_string(headers, method, path, %{
      "date" => date,
      "host" => host,
      "content-length" => content_length,
      "digest" => digest
    })

    [entry] = :public_key.pem_decode(private_key_pem)
    private_key = :public_key.pem_entry_decode(entry)
    signature = :public_key.sign(signature_string, :sha256, private_key)
    signature_b64 = Base.encode64(signature)

    header =
      "Signature " <>
        "keyId=\"#{key_id}\"," <>
        "algorithm=\"rsa-sha256\"," <>
        "headers=\"#{Enum.join(headers, " ")}\"," <>
        "signature=\"#{signature_b64}\""

    Plug.Conn.put_req_header(conn, "authorization", header)
  end

  defp signature_string(headers, method, path, values) do
    headers
    |> Enum.map(fn
      "(request-target)" -> "(request-target): #{String.downcase(method)} " <> path
      "@request-target" -> "@request-target: #{String.downcase(method)} " <> path
      header -> "#{header}: #{Map.get(values, header, "")}"
    end)
    |> Enum.join("\n")
  end

  defp maybe_put_header(conn, headers, header, value) do
    cond do
      header not in headers ->
        conn

      header == "host" ->
        %{conn | host: value}

      true ->
      Plug.Conn.put_req_header(conn, header, value)
    end
  end

  defp digest_header(body) do
    "SHA-256=" <> (:crypto.hash(:sha256, body) |> Base.encode64())
  end

  defp host_header(conn) do
    default_port =
      case conn.scheme do
        :https -> 443
        _ -> 80
      end

    if conn.port == default_port or is_nil(conn.port) do
      conn.host
    else
      "#{conn.host}:#{conn.port}"
    end
  end

  defp date_header do
    date_header(DateTime.utc_now())
  end

  defp date_header(%DateTime{} = dt) do
    year = dt.year
    month = dt.month
    day = dt.day
    hour = dt.hour
    minute = dt.minute
    second = dt.second

    weekday =
      case :calendar.day_of_the_week({year, month, day}) do
        1 -> "Mon"
        2 -> "Tue"
        3 -> "Wed"
        4 -> "Thu"
        5 -> "Fri"
        6 -> "Sat"
        7 -> "Sun"
      end

    month_name =
      case month do
        1 -> "Jan"
        2 -> "Feb"
        3 -> "Mar"
        4 -> "Apr"
        5 -> "May"
        6 -> "Jun"
        7 -> "Jul"
        8 -> "Aug"
        9 -> "Sep"
        10 -> "Oct"
        11 -> "Nov"
        12 -> "Dec"
      end

    :io_lib.format("~s, ~2..0B ~s ~4..0B ~2..0B:~2..0B:~2..0B GMT", [
      weekday,
      day,
      month_name,
      year,
      hour,
      minute,
      second
    ])
    |> IO.iodata_to_binary()
  end

end
