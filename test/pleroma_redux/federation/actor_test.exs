defmodule PleromaRedux.Federation.ActorTest do
  use PleromaRedux.DataCase, async: true

  alias PleromaRedux.Federation.Actor
  alias PleromaRedux.Keys
  alias PleromaRedux.Users

  test "fetch_and_store validates and stores remote actors" do
    actor_url = "https://remote.example/users/alice"
    {public_key, _private_key} = Keys.generate_rsa_keypair()

    expect(PleromaRedux.HTTP.Mock, :get, fn url, headers ->
      assert url == actor_url
      assert {"accept", "application/activity+json, application/ld+json"} in headers
      assert {"user-agent", "pleroma-redux"} in headers

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

  test "fetch_and_store returns :missing_public_key when the actor has no public key" do
    actor_url = "https://remote.example/users/alice"

    expect(PleromaRedux.HTTP.Mock, :get, fn _url, _headers ->
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

    stub(PleromaRedux.HTTP.Mock, :get, fn _url, _headers ->
      flunk("unexpected HTTP fetch for unsafe actor url")
    end)

    assert {:error, :unsafe_url} = Actor.fetch_and_store(actor_url)
  end

  test "fetch_and_store returns :invalid_json for non-json bodies" do
    actor_url = "https://remote.example/users/alice"

    expect(PleromaRedux.HTTP.Mock, :get, fn _url, _headers ->
      {:ok, %{status: 200, body: "nope", headers: []}}
    end)

    assert {:error, :invalid_json} = Actor.fetch_and_store(actor_url)
  end

  test "fetch_and_store returns :actor_fetch_failed for non-2xx responses" do
    actor_url = "https://remote.example/users/alice"

    expect(PleromaRedux.HTTP.Mock, :get, fn _url, _headers ->
      {:ok, %{status: 500, body: %{}, headers: []}}
    end)

    assert {:error, :actor_fetch_failed} = Actor.fetch_and_store(actor_url)
  end
end

