defmodule Egregoros.Federation.ActorTest do
  use Egregoros.DataCase, async: true

  import Mox

  alias Egregoros.Federation.Actor
  alias Egregoros.Keys
  alias Egregoros.Users

  test "fetch_and_store validates and stores remote actors" do
    actor_url = "https://remote.example/users/alice"
    {public_key, _private_key} = Keys.generate_rsa_keypair()
    {ed25519_public_key, _ed25519_private_key} = Keys.generate_ed25519_keypair()
    ed25519_multibase = Keys.ed25519_public_key_multibase(ed25519_public_key)

    expect(Egregoros.HTTP.Mock, :get, fn url, headers ->
      assert url == actor_url
      assert {"accept", "application/activity+json, application/ld+json"} in headers
      assert {"user-agent", "egregoros"} in headers

      {:ok,
       %{
         status: 200,
         body: %{
           "id" => actor_url,
           "type" => "Person",
           "preferredUsername" => "alice",
           "name" => "Alice",
           "summary" => "bio",
           "inbox" => actor_url <> "/inbox",
           "outbox" => actor_url <> "/outbox",
           "icon" => %{"url" => "https://remote.example/media/avatar.png"},
           "image" => %{"url" => "https://remote.example/media/banner.png"},
           "publicKey" => %{
             "id" => actor_url <> "#main-key",
             "owner" => actor_url,
             "publicKeyPem" => public_key
           },
           "assertionMethod" => [
             %{
               "id" => actor_url <> "#ed25519-key",
               "type" => "Multikey",
               "controller" => actor_url,
               "publicKeyMultibase" => ed25519_multibase
             }
           ]
         },
         headers: []
       }}
    end)

    assert {:ok, user} = Actor.fetch_and_store(actor_url)
    assert user.ap_id == actor_url
    assert user.domain == "remote.example"
    assert user.nickname == "alice"
    assert user.local == false
    assert user.private_key == nil
    assert user.public_key == public_key
    assert is_list(user.assertion_method)

    assert Enum.any?(user.assertion_method, fn method ->
             method["id"] == actor_url <> "#ed25519-key" and
               method["type"] == "Multikey" and
               method["controller"] == actor_url and
               method["publicKeyMultibase"] == ed25519_multibase
           end)

    assert user.name == "Alice"
    assert user.bio == "bio"
    assert user.avatar_url == "https://remote.example/media/avatar.png"
    assert user.banner_url == "https://remote.example/media/banner.png"

    assert Users.get_by_ap_id(actor_url)
  end

  test "fetch_and_store broadcasts user updates for newly stored actors" do
    actor_url = "https://remote.example/users/alice"
    {public_key, _private_key} = Keys.generate_rsa_keypair()

    Egregoros.UserEvents.subscribe(actor_url)

    expect(Egregoros.HTTP.Mock, :get, fn _url, _headers ->
      {:ok,
       %{
         status: 200,
         body: %{
           "id" => actor_url,
           "type" => "Person",
           "preferredUsername" => "alice",
           "name" => "Alice",
           "inbox" => actor_url <> "/inbox",
           "outbox" => actor_url <> "/outbox",
           "publicKey" => %{
             "id" => actor_url <> "#main-key",
             "owner" => actor_url,
             "publicKeyPem" => public_key
           }
         },
         headers: []
       }}
    end)

    assert {:ok, _user} = Actor.fetch_and_store(actor_url)
    assert_receive {:user_updated, %{ap_id: ^actor_url}}
  end

  test "fetch_and_store stores custom emoji tags for display names" do
    actor_url = "https://remote.example/users/alice"
    {public_key, _private_key} = Keys.generate_rsa_keypair()

    expect(Egregoros.HTTP.Mock, :get, fn _url, _headers ->
      {:ok,
       %{
         status: 200,
         body: %{
           "id" => actor_url,
           "type" => "Person",
           "preferredUsername" => "alice",
           "name" => ":linux: Alice",
           "tag" => [
             %{
               "type" => "Emoji",
               "name" => ":linux:",
               "icon" => %{"url" => "https://remote.example/emoji/linux.png"}
             }
           ],
           "inbox" => actor_url <> "/inbox",
           "outbox" => actor_url <> "/outbox",
           "publicKey" => %{
             "id" => actor_url <> "#main-key",
             "owner" => actor_url,
             "publicKeyPem" => public_key
           }
         },
         headers: []
       }}
    end)

    assert {:ok, user} = Actor.fetch_and_store(actor_url)
    assert is_list(Map.get(user, :emojis))

    assert %{shortcode: "linux", url: "https://remote.example/emoji/linux.png"} in Map.get(
             user,
             :emojis
           )
  end

  test "fetch_and_store preserves existing profile fields when refetched actors omit them" do
    actor_url = "https://remote.example/users/alice"
    {public_key, _private_key} = Keys.generate_rsa_keypair()

    expect(Egregoros.HTTP.Mock, :get, fn _url, _headers ->
      {:ok,
       %{
         status: 200,
         body: %{
           "id" => actor_url,
           "type" => "Person",
           "preferredUsername" => "alice",
           "name" => "Alice",
           "summary" => "bio",
           "inbox" => actor_url <> "/inbox",
           "outbox" => actor_url <> "/outbox",
           "icon" => %{"url" => "https://remote.example/media/avatar.png"},
           "publicKey" => %{
             "id" => actor_url <> "#main-key",
             "owner" => actor_url,
             "publicKeyPem" => public_key
           }
         },
         headers: []
       }}
    end)

    assert {:ok, _user} = Actor.fetch_and_store(actor_url)

    expect(Egregoros.HTTP.Mock, :get, fn _url, _headers ->
      {:ok,
       %{
         status: 200,
         body: %{
           "id" => actor_url,
           "type" => "Person",
           "preferredUsername" => "alice",
           "inbox" => actor_url <> "/inbox",
           "outbox" => actor_url <> "/outbox",
           "publicKey" => %{
             "id" => actor_url <> "#main-key",
             "owner" => actor_url,
             "publicKeyPem" => public_key
           }
         },
         headers: []
       }}
    end)

    assert {:ok, _user} = Actor.fetch_and_store(actor_url)

    user = Users.get_by_ap_id(actor_url)
    assert user.name == "Alice"
    assert user.bio == "bio"
    assert user.avatar_url == "https://remote.example/media/avatar.png"
  end

  test "fetch_and_store resolves relative icon urls against actor ids" do
    actor_url = "https://remote.example/users/alice"
    {public_key, _private_key} = Keys.generate_rsa_keypair()

    expect(Egregoros.HTTP.Mock, :get, fn _url, _headers ->
      {:ok,
       %{
         status: 200,
         body: %{
           "id" => actor_url,
           "type" => "Person",
           "preferredUsername" => "alice",
           "inbox" => actor_url <> "/inbox",
           "outbox" => actor_url <> "/outbox",
           "icon" => %{"url" => "/media/avatar.png"},
           "publicKey" => %{
             "id" => actor_url <> "#main-key",
             "owner" => actor_url,
             "publicKeyPem" => public_key
           }
         },
         headers: []
       }}
    end)

    assert {:ok, user} = Actor.fetch_and_store(actor_url)
    assert user.avatar_url == "https://remote.example/media/avatar.png"
  end

  test "fetch_and_store retries with signed fetch when endpoints are missing" do
    actor_url = "https://remote.example/users/toast"
    {public_key, _private_key} = Keys.generate_rsa_keypair()

    expect(Egregoros.HTTP.Mock, :get, fn _url, headers ->
      refute List.keyfind(headers, "signature", 0)
      refute List.keyfind(headers, "authorization", 0)

      {:ok,
       %{
         status: 200,
         body: %{
           "id" => actor_url,
           "type" => "Person",
           "preferredUsername" => "toast",
           "publicKey" => %{
             "id" => actor_url <> "#main-key",
             "owner" => actor_url,
             "publicKeyPem" => public_key
           }
         },
         headers: []
       }}
    end)

    expect(Egregoros.HTTP.Mock, :get, fn _url, headers ->
      assert List.keyfind(headers, "signature", 0)
      assert List.keyfind(headers, "authorization", 0)

      {:ok,
       %{
         status: 200,
         body: %{
           "id" => actor_url,
           "type" => "Person",
           "preferredUsername" => "toast",
           "inbox" => actor_url <> "/inbox",
           "outbox" => actor_url <> "/outbox",
           "publicKey" => %{
             "id" => actor_url <> "#main-key",
             "owner" => actor_url,
             "publicKeyPem" => public_key
           }
         },
         headers: []
       }}
    end)

    assert {:ok, user} = Actor.fetch_and_store(actor_url)
    assert user.ap_id == actor_url
    assert user.nickname == "toast"
    assert user.inbox == actor_url <> "/inbox"
    assert user.outbox == actor_url <> "/outbox"
  end

  test "fetch_and_store retries with signed fetch on 401 responses" do
    actor_url = "https://remote.example/users/toast"
    {public_key, _private_key} = Keys.generate_rsa_keypair()

    expect(Egregoros.HTTP.Mock, :get, fn _url, headers ->
      refute List.keyfind(headers, "signature", 0)
      {:ok, %{status: 401, body: "", headers: []}}
    end)

    expect(Egregoros.HTTP.Mock, :get, fn _url, headers ->
      assert List.keyfind(headers, "signature", 0)
      assert List.keyfind(headers, "authorization", 0)

      {:ok,
       %{
         status: 200,
         body: %{
           "id" => actor_url,
           "type" => "Person",
           "preferredUsername" => "toast",
           "inbox" => actor_url <> "/inbox",
           "outbox" => actor_url <> "/outbox",
           "publicKey" => %{
             "id" => actor_url <> "#main-key",
             "owner" => actor_url,
             "publicKeyPem" => public_key
           }
         },
         headers: []
       }}
    end)

    assert {:ok, user} = Actor.fetch_and_store(actor_url)
    assert user.ap_id == actor_url
    assert user.nickname == "toast"
    assert user.inbox == actor_url <> "/inbox"
    assert user.outbox == actor_url <> "/outbox"
  end

  test "fetch_and_store rejects actors without inbox/outbox even after signed fetch" do
    actor_url = "https://remote.example/users/toast"
    {public_key, _private_key} = Keys.generate_rsa_keypair()

    expect(Egregoros.HTTP.Mock, :get, fn _url, headers ->
      refute List.keyfind(headers, "signature", 0)

      {:ok,
       %{
         status: 200,
         body: %{
           "id" => actor_url,
           "type" => "Person",
           "preferredUsername" => "toast",
           "publicKey" => %{
             "id" => actor_url <> "#main-key",
             "owner" => actor_url,
             "publicKeyPem" => public_key
           }
         },
         headers: []
       }}
    end)

    expect(Egregoros.HTTP.Mock, :get, fn _url, headers ->
      assert List.keyfind(headers, "signature", 0)
      assert List.keyfind(headers, "authorization", 0)

      {:ok,
       %{
         status: 200,
         body: %{
           "id" => actor_url,
           "type" => "Person",
           "preferredUsername" => "toast",
           "publicKey" => %{
             "id" => actor_url <> "#main-key",
             "owner" => actor_url,
             "publicKeyPem" => public_key
           }
         },
         headers: []
       }}
    end)

    assert {:error, :missing_inbox} = Actor.fetch_and_store(actor_url)
  end

  test "fetch_and_store supports icon url lists" do
    actor_url = "https://remote.example/users/alice"
    {public_key, _private_key} = Keys.generate_rsa_keypair()

    expect(Egregoros.HTTP.Mock, :get, fn _url, _headers ->
      {:ok,
       %{
         status: 200,
         body: %{
           "id" => actor_url,
           "type" => "Person",
           "preferredUsername" => "alice",
           "inbox" => actor_url <> "/inbox",
           "outbox" => actor_url <> "/outbox",
           "icon" => %{"url" => [%{"href" => "https://remote.example/media/avatar.png"}]},
           "publicKey" => %{
             "id" => actor_url <> "#main-key",
             "owner" => actor_url,
             "publicKeyPem" => public_key
           }
         },
         headers: []
       }}
    end)

    assert {:ok, user} = Actor.fetch_and_store(actor_url)
    assert user.avatar_url == "https://remote.example/media/avatar.png"
  end

  test "fetch_and_store returns :missing_public_key when the actor has no public key" do
    actor_url = "https://remote.example/users/alice"

    expect(Egregoros.HTTP.Mock, :get, fn _url, _headers ->
      {:ok,
       %{
         status: 200,
         body: %{
           "id" => actor_url,
           "type" => "Person",
           "preferredUsername" => "alice",
           "inbox" => actor_url <> "/inbox",
           "outbox" => actor_url <> "/outbox",
           "publicKey" => %{}
         },
         headers: []
       }}
    end)

    assert {:error, :missing_public_key} = Actor.fetch_and_store(actor_url)
    refute Users.get_by_ap_id(actor_url)
  end

  test "fetch_and_store rejects unsafe actor urls" do
    actor_url = "http://127.0.0.1/users/alice"

    stub(Egregoros.HTTP.Mock, :get, fn _url, _headers ->
      flunk("unexpected HTTP fetch for unsafe actor url")
    end)

    assert {:error, :unsafe_url} = Actor.fetch_and_store(actor_url)
  end

  test "fetch_and_store can be configured to allow federation-box hostnames" do
    actor_url = "https://private.example/users/alice"
    {public_key, _private_key} = Keys.generate_rsa_keypair()

    stub(Egregoros.Config.Mock, :get, fn
      :allow_private_federation, _default -> true
      key, default -> Egregoros.Config.Stub.get(key, default)
    end)

    Egregoros.DNS.Mock
    |> expect(:lookup_ips, 0, fn _host ->
      flunk("unexpected DNS lookup for federation-box actor fetch")
    end)

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == actor_url

      {:ok,
       %{
         status: 200,
         body: %{
           "id" => actor_url,
           "type" => "Person",
           "preferredUsername" => "alice",
           "inbox" => actor_url <> "/inbox",
           "outbox" => actor_url <> "/outbox",
           "publicKey" => %{
             "id" => actor_url <> "#main-key",
             "owner" => actor_url,
             "publicKeyPem" => public_key
           }
         },
         headers: []
       }}
    end)

    assert {:ok, user} = Actor.fetch_and_store(actor_url)
    assert user.ap_id == actor_url
  end

  test "fetch_and_store returns :invalid_json for non-json bodies" do
    actor_url = "https://remote.example/users/alice"

    expect(Egregoros.HTTP.Mock, :get, fn _url, _headers ->
      {:ok, %{status: 200, body: "nope", headers: []}}
    end)

    assert {:error, :invalid_json} = Actor.fetch_and_store(actor_url)
  end

  test "fetch_and_store returns :actor_fetch_failed for non-2xx responses" do
    actor_url = "https://remote.example/users/alice"

    expect(Egregoros.HTTP.Mock, :get, fn _url, _headers ->
      {:ok, %{status: 500, body: %{}, headers: []}}
    end)

    assert {:error, :actor_fetch_failed} = Actor.fetch_and_store(actor_url)
  end

  test "fetch_and_store rejects actors whose id does not match the fetched url" do
    actor_url = "https://remote.example/users/alice"
    {public_key, _private_key} = Keys.generate_rsa_keypair()

    expect(Egregoros.HTTP.Mock, :get, fn _url, _headers ->
      {:ok,
       %{
         status: 200,
         body: %{
           "id" => "https://evil.example/users/alice",
           "type" => "Person",
           "preferredUsername" => "alice",
           "inbox" => actor_url <> "/inbox",
           "outbox" => actor_url <> "/outbox",
           "publicKey" => %{
             "id" => actor_url <> "#main-key",
             "owner" => actor_url,
             "publicKeyPem" => public_key
           }
         },
         headers: []
       }}
    end)

    assert {:error, :actor_id_mismatch} = Actor.fetch_and_store(actor_url)
    refute Users.get_by_ap_id(actor_url)
  end

  test "fetch_and_store rejects actors with unsafe inbox urls" do
    actor_url = "https://remote.example/users/alice"
    {public_key, _private_key} = Keys.generate_rsa_keypair()

    expect(Egregoros.HTTP.Mock, :get, fn _url, _headers ->
      {:ok,
       %{
         status: 200,
         body: %{
           "id" => actor_url,
           "type" => "Person",
           "preferredUsername" => "alice",
           "inbox" => "http://127.0.0.1/inbox",
           "outbox" => actor_url <> "/outbox",
           "publicKey" => %{
             "id" => actor_url <> "#main-key",
             "owner" => actor_url,
             "publicKeyPem" => public_key
           }
         },
         headers: []
       }}
    end)

    assert {:error, :unsafe_url} = Actor.fetch_and_store(actor_url)
    refute Users.get_by_ap_id(actor_url)
  end

  test "upsert_from_map rejects non-map inputs" do
    assert {:error, :invalid_actor} = Actor.upsert_from_map("nope")
  end

  test "upsert_from_map rejects maps without ids" do
    assert {:error, :invalid_actor} = Actor.upsert_from_map(%{"type" => "Person"})
  end

  test "upsert_from_map returns a specific error when required fields are missing" do
    actor_url = "https://remote.example/users/missing-key-#{Ecto.UUID.generate()}"

    assert {:error, :missing_public_key} =
             Actor.upsert_from_map(%{
               "id" => actor_url,
               "type" => "Person",
               "inbox" => actor_url <> "/inbox",
               "outbox" => actor_url <> "/outbox",
               "publicKey" => %{}
             })
  end

  test "fetch_and_store decodes JSON bodies and stores the actor" do
    actor_url = "https://remote.example/users/json-#{Ecto.UUID.generate()}"
    {public_key, _private_key} = Keys.generate_rsa_keypair()

    actor = %{
      "id" => actor_url,
      "type" => "Person",
      "preferredUsername" => "json-#{System.unique_integer([:positive])}",
      "inbox" => actor_url <> "/inbox",
      "outbox" => actor_url <> "/outbox",
      "publicKey" => %{
        "id" => actor_url <> "#main-key",
        "owner" => actor_url,
        "publicKeyPem" => public_key
      }
    }

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == actor_url
      {:ok, %{status: 200, body: Jason.encode!(actor), headers: []}}
    end)

    assert {:ok, user} = Actor.fetch_and_store(actor_url)
    assert user.ap_id == actor_url
    assert user.public_key == public_key
  end

  test "fetch_and_store returns :invalid_json for unexpected body types" do
    actor_url = "https://remote.example/users/bad-body-#{Ecto.UUID.generate()}"

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == actor_url
      {:ok, %{status: 200, body: 123, headers: []}}
    end)

    assert {:error, :invalid_json} = Actor.fetch_and_store(actor_url)
  end

  test "fetch_and_store propagates HTTP transport errors" do
    actor_url = "https://remote.example/users/timeout-#{Ecto.UUID.generate()}"

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == actor_url
      {:error, :timeout}
    end)

    assert {:error, :timeout} = Actor.fetch_and_store(actor_url)
  end

  test "fetch_and_store falls back to the unsigned response when signed fetch fails" do
    actor_url = "https://remote.example/users/signed-fail-#{Ecto.UUID.generate()}"
    {public_key, _private_key} = Keys.generate_rsa_keypair()

    expect(Egregoros.HTTP.Mock, :get, fn _url, headers ->
      refute List.keyfind(headers, "signature", 0)
      refute List.keyfind(headers, "authorization", 0)

      {:ok,
       %{
         status: 200,
         body: %{
           "id" => actor_url,
           "type" => "Person",
           "preferredUsername" => "toast",
           "publicKey" => %{
             "id" => actor_url <> "#main-key",
             "owner" => actor_url,
             "publicKeyPem" => public_key
           }
         },
         headers: []
       }}
    end)

    expect(Egregoros.HTTP.Mock, :get, fn _url, headers ->
      assert List.keyfind(headers, "signature", 0)
      assert List.keyfind(headers, "authorization", 0)

      {:ok, %{status: 500, body: %{}, headers: []}}
    end)

    assert {:error, :missing_inbox} = Actor.fetch_and_store(actor_url)
  end

  test "fetch_and_store falls back to nickname 'unknown' when the actor id has no path" do
    actor_url = "https://remote.example"
    {public_key, _private_key} = Keys.generate_rsa_keypair()

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == actor_url

      {:ok,
       %{
         status: 200,
         body: %{
           "id" => actor_url,
           "type" => "Person",
           "inbox" => actor_url <> "/inbox",
           "outbox" => actor_url <> "/outbox",
           "publicKey" => %{
             "id" => actor_url <> "#main-key",
             "owner" => actor_url,
             "publicKeyPem" => public_key
           }
         },
         headers: []
       }}
    end)

    assert {:ok, user} = Actor.fetch_and_store(actor_url)
    assert user.nickname == "unknown"
  end

  test "fetch_and_store persists moved_to, also_known_as, and locked flags" do
    actor_url = "https://remote.example/users/alice-#{Ecto.UUID.generate()}"
    {public_key, _private_key} = Keys.generate_rsa_keypair()

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == actor_url

      {:ok,
       %{
         status: 200,
         body: %{
           "id" => actor_url,
           "type" => "Person",
           "preferredUsername" => "alice-#{System.unique_integer([:positive])}",
           "inbox" => actor_url <> "/inbox",
           "outbox" => actor_url <> "/outbox",
           "manuallyApprovesFollowers" => "true",
           "movedTo" => %{"id" => "/users/new"},
           "alsoKnownAs" => [
             "https://remote.example/users/aka",
             %{id: "https://remote.example/users/aka2"},
             "http://127.0.0.1/users/unsafe",
             123
           ],
           "icon" => %{"url" => ""},
           "image" => %{"url" => "javascript:alert(1)"},
           "publicKey" => %{
             "id" => actor_url <> "#main-key",
             "owner" => actor_url,
             "publicKeyPem" => public_key
           }
         },
         headers: []
       }}
    end)

    assert {:ok, user} = Actor.fetch_and_store(actor_url)
    assert user.locked == true
    assert user.moved_to_ap_id == "https://remote.example/users/new"
    assert "https://remote.example/users/aka" in user.also_known_as
    assert "https://remote.example/users/aka2" in user.also_known_as
    refute "http://127.0.0.1/users/unsafe" in user.also_known_as
    assert user.avatar_url == nil
    assert user.banner_url == nil
  end

  test "fetch_and_store ignores unsafe movedTo values" do
    actor_url = "https://remote.example/users/moved-unsafe-#{Ecto.UUID.generate()}"
    {public_key, _private_key} = Keys.generate_rsa_keypair()

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == actor_url

      {:ok,
       %{
         status: 200,
         body: %{
           "id" => actor_url,
           "type" => "Person",
           "preferredUsername" => "moved-unsafe-#{System.unique_integer([:positive])}",
           "inbox" => actor_url <> "/inbox",
           "outbox" => actor_url <> "/outbox",
           "movedTo" => "http://127.0.0.1/users/evil",
           "publicKey" => %{
             "id" => actor_url <> "#main-key",
             "owner" => actor_url,
             "publicKeyPem" => public_key
           }
         },
         headers: []
       }}
    end)

    assert {:ok, user} = Actor.fetch_and_store(actor_url)
    assert user.moved_to_ap_id == nil
  end
end
