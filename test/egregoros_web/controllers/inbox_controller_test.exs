defmodule EgregorosWeb.InboxControllerTest do
  use EgregorosWeb.ConnCase, async: true

  alias Egregoros.Objects
  alias Egregoros.Relationships
  alias Egregoros.Users
  alias Egregoros.Workers.IngestActivity

  test "POST /users/:nickname/inbox ingests activity", %{conn: conn} do
    {:ok, frank} = Users.create_local_user("frank")
    {public_key, private_key} = Egregoros.Keys.generate_rsa_keypair()

    {:ok, alice} =
      Users.create_user(%{
        nickname: "alice",
        ap_id: "https://remote.example/users/alice",
        inbox: "https://remote.example/users/alice/inbox",
        outbox: "https://remote.example/users/alice/outbox",
        public_key: public_key,
        private_key: private_key,
        local: false
      })

    :ok = follow!(frank.ap_id, alice.ap_id)

    note = %{
      "id" => "https://remote.example/objects/1",
      "type" => "Note",
      "attributedTo" => "https://remote.example/users/alice",
      "content" => "Hello from remote"
    }

    create = %{
      "id" => "https://remote.example/activities/create/1",
      "type" => "Create",
      "actor" => "https://remote.example/users/alice",
      "object" => note
    }

    conn =
      conn
      |> sign_request(
        "post",
        "/users/frank/inbox",
        private_key,
        "https://remote.example/users/alice#main-key"
      )
      |> post("/users/frank/inbox", create)

    assert response(conn, 202)

    assert_enqueued(
      worker: IngestActivity,
      queue: "federation_incoming",
      args: %{"activity" => create, "inbox_user_ap_id" => frank.ap_id}
    )

    assert :ok =
             perform_job(IngestActivity, %{
               "activity" => create,
               "inbox_user_ap_id" => frank.ap_id
             })

    assert Objects.get_by_ap_id(note["id"])
  end

  test "POST /users/:nickname/inbox discards a Follow not targeting that inbox user", %{
    conn: conn
  } do
    {:ok, frank} = Users.create_local_user("frank")
    {:ok, bob} = Users.create_local_user("bob")

    {public_key, private_key} = Egregoros.Keys.generate_rsa_keypair()

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

    follow = %{
      "id" => "https://remote.example/activities/follow/1",
      "type" => "Follow",
      "actor" => "https://remote.example/users/alice",
      "object" => bob.ap_id
    }

    conn =
      conn
      |> sign_request(
        "post",
        "/users/frank/inbox",
        private_key,
        "https://remote.example/users/alice#main-key"
      )
      |> post("/users/frank/inbox", follow)

    assert response(conn, 202)

    assert_enqueued(
      worker: IngestActivity,
      queue: "federation_incoming",
      args: %{"activity" => follow, "inbox_user_ap_id" => frank.ap_id}
    )

    assert {:discard, :not_targeted} =
             perform_job(IngestActivity, %{
               "activity" => follow,
               "inbox_user_ap_id" => frank.ap_id
             })

    refute Objects.get_by_ap_id(follow["id"])
    refute Relationships.get_by_type_actor_object("Follow", follow["actor"], bob.ap_id)
  end

  test "POST /users/:nickname/inbox discards a Create not targeting that inbox user", %{
    conn: conn
  } do
    {:ok, frank} = Users.create_local_user("frank")
    {public_key, private_key} = Egregoros.Keys.generate_rsa_keypair()

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
      "id" => "https://remote.example/objects/1-not-targeted",
      "type" => "Note",
      "attributedTo" => "https://remote.example/users/alice",
      "content" => "Hello from remote"
    }

    create = %{
      "id" => "https://remote.example/activities/create/1-not-targeted",
      "type" => "Create",
      "actor" => "https://remote.example/users/alice",
      "object" => note
    }

    conn =
      conn
      |> sign_request(
        "post",
        "/users/frank/inbox",
        private_key,
        "https://remote.example/users/alice#main-key"
      )
      |> post("/users/frank/inbox", create)

    assert response(conn, 202)

    assert_enqueued(
      worker: IngestActivity,
      args: %{"activity" => create, "inbox_user_ap_id" => frank.ap_id}
    )

    assert {:discard, :not_targeted} =
             perform_job(IngestActivity, %{
               "activity" => create,
               "inbox_user_ap_id" => frank.ap_id
             })

    refute Objects.get_by_ap_id(note["id"])
  end

  test "POST /users/:nickname/inbox discards a Like not targeting that inbox user", %{
    conn: conn
  } do
    {:ok, frank} = Users.create_local_user("frank")
    {:ok, bob} = Users.create_local_user("bob")

    {:ok, _} =
      Objects.upsert_object(%{
        ap_id: "https://egregoros.example/objects/bob-post",
        type: "Note",
        actor: bob.ap_id,
        object: nil,
        data: %{"id" => "https://egregoros.example/objects/bob-post", "type" => "Note"},
        local: true
      })

    {public_key, private_key} = Egregoros.Keys.generate_rsa_keypair()

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

    like = %{
      "id" => "https://remote.example/activities/like/1-not-targeted",
      "type" => "Like",
      "actor" => "https://remote.example/users/alice",
      "object" => "https://egregoros.example/objects/bob-post"
    }

    conn =
      conn
      |> sign_request(
        "post",
        "/users/frank/inbox",
        private_key,
        "https://remote.example/users/alice#main-key"
      )
      |> post("/users/frank/inbox", like)

    assert response(conn, 202)

    assert_enqueued(
      worker: IngestActivity,
      args: %{"activity" => like, "inbox_user_ap_id" => frank.ap_id}
    )

    assert {:discard, :not_targeted} =
             perform_job(IngestActivity, %{
               "activity" => like,
               "inbox_user_ap_id" => frank.ap_id
             })

    refute Objects.get_by_ap_id(like["id"])
    refute Relationships.get_by_type_actor_object("Like", like["actor"], like["object"])
  end

  test "POST /users/:nickname/inbox discards an Accept not targeting that inbox user", %{
    conn: conn
  } do
    {:ok, frank} = Users.create_local_user("frank")
    {:ok, bob} = Users.create_local_user("bob")

    {public_key, private_key} = Egregoros.Keys.generate_rsa_keypair()

    {:ok, alice} =
      Users.create_user(%{
        nickname: "alice",
        ap_id: "https://remote.example/users/alice",
        inbox: "https://remote.example/users/alice/inbox",
        outbox: "https://remote.example/users/alice/outbox",
        public_key: public_key,
        private_key: private_key,
        local: false
      })

    {:ok, _} =
      Objects.upsert_object(%{
        ap_id: "https://egregoros.example/activities/follow/bob-to-alice",
        type: "Follow",
        actor: bob.ap_id,
        object: alice.ap_id,
        data: %{
          "id" => "https://egregoros.example/activities/follow/bob-to-alice",
          "type" => "Follow",
          "actor" => bob.ap_id,
          "object" => alice.ap_id
        },
        local: true
      })

    accept = %{
      "id" => "https://remote.example/activities/accept/1-not-targeted",
      "type" => "Accept",
      "actor" => "https://remote.example/users/alice",
      "object" => "https://egregoros.example/activities/follow/bob-to-alice"
    }

    conn =
      conn
      |> sign_request(
        "post",
        "/users/frank/inbox",
        private_key,
        "https://remote.example/users/alice#main-key"
      )
      |> post("/users/frank/inbox", accept)

    assert response(conn, 202)

    assert_enqueued(
      worker: IngestActivity,
      args: %{"activity" => accept, "inbox_user_ap_id" => frank.ap_id}
    )

    assert {:discard, :not_targeted} =
             perform_job(IngestActivity, %{
               "activity" => accept,
               "inbox_user_ap_id" => frank.ap_id
             })

    refute Objects.get_by_ap_id(accept["id"])
  end

  test "POST /users/:nickname/inbox accepts a Create with attachments and blank content", %{
    conn: conn
  } do
    {:ok, frank} = Users.create_local_user("frank")
    {public_key, private_key} = Egregoros.Keys.generate_rsa_keypair()

    {:ok, alice} =
      Users.create_user(%{
        nickname: "alice",
        ap_id: "https://remote.example/users/alice",
        inbox: "https://remote.example/users/alice/inbox",
        outbox: "https://remote.example/users/alice/outbox",
        public_key: public_key,
        private_key: private_key,
        local: false
      })

    :ok = follow!(frank.ap_id, alice.ap_id)

    note = %{
      "id" => "https://remote.example/objects/1-attachment-only",
      "type" => "Note",
      "attributedTo" => "https://remote.example/users/alice",
      "content" => "",
      "attachment" => [
        %{
          "type" => "Document",
          "mediaType" => "image/webp",
          "url" => "https://cdn.remote.example/media/1.webp",
          "name" => ""
        }
      ]
    }

    create = %{
      "id" => "https://remote.example/activities/create/1-attachment-only",
      "type" => "Create",
      "actor" => "https://remote.example/users/alice",
      "object" => note
    }

    conn =
      conn
      |> sign_request(
        "post",
        "/users/frank/inbox",
        private_key,
        "https://remote.example/users/alice#main-key"
      )
      |> post("/users/frank/inbox", create)

    assert response(conn, 202)

    assert_enqueued(
      worker: IngestActivity,
      args: %{"activity" => create, "inbox_user_ap_id" => frank.ap_id}
    )

    assert :ok =
             perform_job(IngestActivity, %{
               "activity" => create,
               "inbox_user_ap_id" => frank.ap_id
             })

    object = Objects.get_by_ap_id(note["id"])
    assert object
    assert object.data["content"] == ""
    assert is_list(object.data["attachment"])

    assert Enum.at(object.data["attachment"], 0)["url"] ==
             "https://cdn.remote.example/media/1.webp"
  end

  test "POST /users/:nickname/inbox accepts signature with digest and host", %{conn: conn} do
    {:ok, frank} = Users.create_local_user("frank")
    {public_key, private_key} = Egregoros.Keys.generate_rsa_keypair()

    {:ok, alice} =
      Users.create_user(%{
        nickname: "alice",
        ap_id: "https://remote.example/users/alice",
        inbox: "https://remote.example/users/alice/inbox",
        outbox: "https://remote.example/users/alice/outbox",
        public_key: public_key,
        private_key: private_key,
        local: false
      })

    :ok = follow!(frank.ap_id, alice.ap_id)

    note = %{
      "id" => "https://remote.example/objects/1-digest",
      "type" => "Note",
      "attributedTo" => "https://remote.example/users/alice",
      "content" => "Hello with digest"
    }

    create = %{
      "id" => "https://remote.example/activities/create/1-digest",
      "type" => "Create",
      "actor" => "https://remote.example/users/alice",
      "object" => note
    }

    body = Jason.encode!(create)
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

    assert_enqueued(
      worker: IngestActivity,
      args: %{"activity" => create, "inbox_user_ap_id" => frank.ap_id}
    )

    assert :ok =
             perform_job(IngestActivity, %{
               "activity" => create,
               "inbox_user_ap_id" => frank.ap_id
             })

    assert Objects.get_by_ap_id(note["id"])
  end

  test "POST /users/:nickname/inbox accepts signature header without scheme prefix", %{conn: conn} do
    {:ok, frank} = Users.create_local_user("frank")
    {public_key, private_key} = Egregoros.Keys.generate_rsa_keypair()

    {:ok, alice} =
      Users.create_user(%{
        nickname: "alice",
        ap_id: "https://remote.example/users/alice",
        inbox: "https://remote.example/users/alice/inbox",
        outbox: "https://remote.example/users/alice/outbox",
        public_key: public_key,
        private_key: private_key,
        local: false
      })

    :ok = follow!(frank.ap_id, alice.ap_id)

    note = %{
      "id" => "https://remote.example/objects/1-signature-header",
      "type" => "Note",
      "attributedTo" => "https://remote.example/users/alice",
      "content" => "Hello via signature header"
    }

    create = %{
      "id" => "https://remote.example/activities/create/1-signature-header",
      "type" => "Create",
      "actor" => "https://remote.example/users/alice",
      "object" => note
    }

    conn =
      conn
      |> sign_request(
        "post",
        "/users/frank/inbox",
        private_key,
        "https://remote.example/users/alice#main-key"
      )
      |> move_authorization_to_signature_header()
      |> post("/users/frank/inbox", create)

    assert response(conn, 202)

    assert_enqueued(
      worker: IngestActivity,
      args: %{"activity" => create, "inbox_user_ap_id" => frank.ap_id}
    )

    assert :ok =
             perform_job(IngestActivity, %{
               "activity" => create,
               "inbox_user_ap_id" => frank.ap_id
             })

    assert Objects.get_by_ap_id(note["id"])
  end

  test "POST /users/:nickname/inbox accepts signature behind https proxy (x-forwarded headers)",
       %{
         conn: conn
       } do
    {:ok, frank} = Users.create_local_user("frank")
    {public_key, private_key} = Egregoros.Keys.generate_rsa_keypair()

    {:ok, alice} =
      Users.create_user(%{
        nickname: "alice",
        ap_id: "https://remote.example/users/alice",
        inbox: "https://remote.example/users/alice/inbox",
        outbox: "https://remote.example/users/alice/outbox",
        public_key: public_key,
        private_key: private_key,
        local: false
      })

    :ok = follow!(frank.ap_id, alice.ap_id)

    note = %{
      "id" => "https://remote.example/objects/1-proxy",
      "type" => "Note",
      "attributedTo" => "https://remote.example/users/alice",
      "content" => "Hello through proxy"
    }

    create = %{
      "id" => "https://remote.example/activities/create/1-proxy",
      "type" => "Create",
      "actor" => "https://remote.example/users/alice",
      "object" => note
    }

    body = Jason.encode!(create)
    headers = ["(request-target)", "host", "date", "digest", "content-length"]
    headers = Enum.map(headers, &String.downcase/1)

    date = date_header()
    host = "egregoros.ngrok.dev"
    digest = digest_header(body)
    content_length = Integer.to_string(byte_size(body))

    signature_string =
      signature_string(headers, "post", "/users/frank/inbox", %{
        "date" => date,
        "host" => host,
        "content-length" => content_length,
        "digest" => digest
      })

    [entry] = :public_key.pem_decode(private_key)
    private_key = :public_key.pem_entry_decode(entry)
    signature = :public_key.sign(signature_string, :sha256, private_key)
    signature_b64 = Base.encode64(signature)

    header =
      "keyId=\"https://remote.example/users/alice#main-key\"," <>
        "algorithm=\"rsa-sha256\"," <>
        "headers=\"#{Enum.join(headers, " ")}\"," <>
        "signature=\"#{signature_b64}\""

    conn =
      conn
      |> Map.put(:scheme, :http)
      |> Map.put(:host, host)
      |> Map.put(:port, 4000)
      |> put_req_header("x-forwarded-proto", "https")
      |> put_req_header("x-forwarded-port", "443")
      |> put_req_header("content-type", "application/activity+json")
      |> put_req_header("accept", "application/activity+json")
      |> put_req_header("date", date)
      |> put_req_header("digest", digest)
      |> put_req_header("content-length", content_length)
      |> put_req_header("signature", header)
      |> post("/users/frank/inbox", body)

    assert response(conn, 202)

    assert_enqueued(
      worker: IngestActivity,
      args: %{"activity" => create, "inbox_user_ap_id" => frank.ap_id}
    )

    assert :ok =
             perform_job(IngestActivity, %{
               "activity" => create,
               "inbox_user_ap_id" => frank.ap_id
             })

    assert Objects.get_by_ap_id(note["id"])
  end

  test "POST /users/:nickname/inbox rejects mismatched digest", %{conn: conn} do
    {:ok, _user} = Users.create_local_user("frank")
    {public_key, private_key} = Egregoros.Keys.generate_rsa_keypair()

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

    tampered_note = Map.put(note, "content", "Tampered content")

    signed_create = %{
      "id" => "https://remote.example/activities/create/1-digest-mismatch",
      "type" => "Create",
      "actor" => "https://remote.example/users/alice",
      "object" => note
    }

    tampered_create = %{
      "id" => "https://remote.example/activities/create/1-digest-mismatch",
      "type" => "Create",
      "actor" => "https://remote.example/users/alice",
      "object" => tampered_note
    }

    signed_body = Jason.encode!(signed_create)
    sent_body = Jason.encode!(tampered_create)

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

  test "POST /users/:nickname/inbox rejects signature actor mismatch", %{conn: conn} do
    {:ok, _user} = Users.create_local_user("frank")
    {public_key, private_key} = Egregoros.Keys.generate_rsa_keypair()

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
      "id" => "https://remote.example/objects/1-actor-mismatch",
      "type" => "Note",
      "attributedTo" => "https://remote.example/users/bob",
      "content" => "Hello from bob"
    }

    create = %{
      "id" => "https://remote.example/activities/create/1-actor-mismatch",
      "type" => "Create",
      "actor" => "https://remote.example/users/bob",
      "object" => note
    }

    conn =
      conn
      |> sign_request(
        "post",
        "/users/frank/inbox",
        private_key,
        "https://remote.example/users/alice#main-key"
      )
      |> post("/users/frank/inbox", create)

    assert response(conn, 401)
    refute Objects.get_by_ap_id(note["id"])
  end

  test "POST /users/:nickname/inbox rejects old date signature", %{conn: conn} do
    {:ok, _user} = Users.create_local_user("frank")
    {public_key, private_key} = Egregoros.Keys.generate_rsa_keypair()

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

    create = %{
      "id" => "https://remote.example/activities/create/1-old-date",
      "type" => "Create",
      "actor" => "https://remote.example/users/alice",
      "object" => note
    }

    old_date = DateTime.utc_now() |> DateTime.add(-400, :second) |> date_header()

    conn =
      conn
      |> put_req_header("date", old_date)
      |> sign_request(
        "post",
        "/users/frank/inbox",
        private_key,
        "https://remote.example/users/alice#main-key"
      )
      |> post("/users/frank/inbox", create)

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

    create = %{
      "id" => "https://remote.example/activities/create/2",
      "type" => "Create",
      "actor" => "https://remote.example/users/alice",
      "object" => note
    }

    conn = post(conn, "/users/frank/inbox", create)
    assert response(conn, 401)

    refute Objects.get_by_ap_id(note["id"])
  end

  defp follow!(follower_ap_id, followed_ap_id)
       when is_binary(follower_ap_id) and is_binary(followed_ap_id) do
    {:ok, _} =
      Relationships.upsert_relationship(%{
        type: "Follow",
        actor: follower_ap_id,
        object: followed_ap_id,
        activity_ap_id: Ecto.UUID.generate()
      })

    :ok
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

    signature_string =
      signature_string(headers, method, path, %{
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

  defp move_authorization_to_signature_header(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Signature " <> rest] ->
        conn
        |> Plug.Conn.delete_req_header("authorization")
        |> Plug.Conn.put_req_header("signature", rest)

      _ ->
        conn
    end
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
