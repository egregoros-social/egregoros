defmodule Egregoros.Federation.ActorTest do
  use Egregoros.DataCase, async: true

  import Mox

  alias Egregoros.Federation.Actor
  alias Egregoros.Keys
  alias Egregoros.Users

  test "fetch_and_store validates and stores remote actors" do
    actor_url = "https://remote.example/users/alice"
    {public_key, _private_key} = Keys.generate_rsa_keypair()

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
    assert user.domain == "remote.example"
    assert user.nickname == "alice"
    assert user.local == false
    assert user.private_key == nil
    assert user.public_key == public_key
    assert user.name == "Alice"
    assert user.bio == "bio"
    assert user.avatar_url == "https://remote.example/media/avatar.png"

    assert Users.get_by_ap_id(actor_url)
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
end
