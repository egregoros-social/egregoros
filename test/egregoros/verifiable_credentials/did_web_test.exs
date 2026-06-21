defmodule Egregoros.VerifiableCredentials.DidWebTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.Keys
  alias Egregoros.User
  alias Egregoros.Federation.InstanceActor
  alias Egregoros.VerifiableCredentials.DidWeb

  test "helpers return nil for invalid inputs" do
    assert DidWeb.did_from_url(nil) == nil
    assert DidWeb.did_from_verification_method(nil) == nil
    assert DidWeb.verification_method_id(nil) == nil
    assert DidWeb.public_key_multibase(nil) == nil
    assert DidWeb.did_document_url("   ") == nil
    assert DidWeb.did_document_url(nil) == nil
    assert DidWeb.did_base_url(nil) == nil
    assert {:error, :invalid_actor} = DidWeb.instance_document(%{})
  end

  test "did_base_url/1 returns the base URL for did:web domain identifiers" do
    assert DidWeb.did_base_url("did:web:remote.example") == "https://remote.example"
  end

  test "did_base_url/1 returns the base URL for did:web identifiers with path segments" do
    assert DidWeb.did_base_url("did:web:remote.example:user") == "https://remote.example/user"
  end

  test "did_base_url/1 returns the base URL for did:web identifiers with port segments" do
    assert DidWeb.did_base_url("did:web:remote.example:8443") == "https://remote.example:8443"
  end

  test "did_base_url/1 returns nil for non did:web identifiers" do
    assert DidWeb.did_base_url("did:key:z6Mk...") == nil
  end

  test "did_document_url/1 derives the did.json URL for did:web identifiers" do
    assert DidWeb.did_document_url("did:web:remote.example") ==
             "https://remote.example/.well-known/did.json"

    assert DidWeb.did_document_url("did:web:remote.example:user") ==
             "https://remote.example/user/did.json"

    assert DidWeb.did_document_url("did:web:remote.example:8443") ==
             "https://remote.example:8443/.well-known/did.json"
  end

  test "did_from_url/1 returns a did:web identifier for https URLs" do
    assert DidWeb.did_from_url("https://example.com/users/alice") == "did:web:example.com"

    assert DidWeb.did_from_url("https://example.com:8443/users/alice") ==
             "did:web:example.com:8443"
  end

  test "did_from_verification_method/1 extracts did:web identifiers from verification method ids" do
    assert DidWeb.did_from_verification_method("did:web:remote.example#ed25519-key") ==
             "did:web:remote.example"

    assert DidWeb.did_from_verification_method("https://example.com/#key") == nil
  end

  test "verification_method_id/1 appends the ed25519 key fragment" do
    assert DidWeb.verification_method_id("did:web:remote.example") ==
             "did:web:remote.example#ed25519-key"

    assert DidWeb.verification_method_id("") == nil
  end

  test "resolve_public_key/2 returns an ed25519 public key for did:web documents" do
    {public_key, _private_key} = Keys.generate_ed25519_keypair()
    multibase = Keys.ed25519_public_key_multibase(public_key)

    did = "did:web:example.com"
    verification_method = did <> "#ed25519-key"
    actor_ap_id = "https://example.com/users/alice"

    document = %{
      "id" => did,
      "alsoKnownAs" => [actor_ap_id],
      "verificationMethod" => [
        %{
          "id" => verification_method,
          "type" => "Multikey",
          "controller" => did,
          "publicKeyMultibase" => multibase
        }
      ],
      "assertionMethod" => [verification_method]
    }

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == "https://example.com/.well-known/did.json"
      {:ok, %{status: 200, body: document, headers: []}}
    end)

    assert {:ok, ^public_key} = DidWeb.resolve_public_key(verification_method, actor_ap_id)
  end

  test "resolve_public_key/2 decodes JSON string bodies" do
    {public_key, _private_key} = Keys.generate_ed25519_keypair()
    multibase = Keys.ed25519_public_key_multibase(public_key)

    did = "did:web:example.com"
    verification_method = did <> "#ed25519-key"

    document = %{
      "id" => did,
      "verificationMethod" => [
        %{
          "id" => verification_method,
          "type" => "Multikey",
          "controller" => did,
          "publicKeyMultibase" => multibase
        }
      ],
      "assertionMethod" => [verification_method]
    }

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == "https://example.com/.well-known/did.json"
      {:ok, %{status: 200, body: Jason.encode!(document), headers: []}}
    end)

    assert {:ok, ^public_key} = DidWeb.resolve_public_key(verification_method)
  end

  test "resolve_public_key/2 rejects documents whose id does not match the did" do
    verification_method = "did:web:example.com#ed25519-key"

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == "https://example.com/.well-known/did.json"
      {:ok, %{status: 200, body: %{"id" => "did:web:other.example"}, headers: []}}
    end)

    assert {:error, :invalid_did_document} = DidWeb.resolve_public_key(verification_method, nil)
  end

  test "resolve_public_key/2 rejects blank actor ids" do
    verification_method = "did:web:example.com#ed25519-key"

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == "https://example.com/.well-known/did.json"
      {:ok, %{status: 200, body: %{"id" => "did:web:example.com"}, headers: []}}
    end)

    assert {:error, :invalid_actor} = DidWeb.resolve_public_key(verification_method, " ")
  end

  test "resolve_public_key/2 rejects non-json response bodies" do
    verification_method = "did:web:example.com#ed25519-key"

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == "https://example.com/.well-known/did.json"
      {:ok, %{status: 200, body: 123, headers: []}}
    end)

    assert {:error, :invalid_json} = DidWeb.resolve_public_key(verification_method, nil)
  end

  test "resolve_public_key/2 rejects non-binary actor ids" do
    verification_method = "did:web:example.com#ed25519-key"

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == "https://example.com/.well-known/did.json"
      {:ok, %{status: 200, body: %{"id" => "did:web:example.com"}, headers: []}}
    end)

    assert {:error, :invalid_actor} = DidWeb.resolve_public_key(verification_method, 123)
  end

  test "resolve_public_key/2 rejects assertion methods expressed as non-id values" do
    verification_method = "did:web:example.com#ed25519-key"

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == "https://example.com/.well-known/did.json"

      {:ok,
       %{
         status: 200,
         body: %{"id" => "did:web:example.com", "assertionMethod" => [123]},
         headers: []
       }}
    end)

    assert {:error, :unauthorized_verification_method} =
             DidWeb.resolve_public_key(verification_method, nil)
  end

  test "resolve_public_key/2 skips malformed verification methods in did documents" do
    verification_method = "did:web:example.com#ed25519-key"

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == "https://example.com/.well-known/did.json"

      {:ok,
       %{
         status: 200,
         body: %{
           "id" => "did:web:example.com",
           "verificationMethod" => [123],
           "assertionMethod" => [verification_method]
         },
         headers: []
       }}
    end)

    assert {:error, :missing_key} = DidWeb.resolve_public_key(verification_method, nil)
  end

  test "resolve_public_key/2 supports controller maps with atom keys" do
    {public_key, _private_key} = Keys.generate_ed25519_keypair()
    multibase = Keys.ed25519_public_key_multibase(public_key)

    did = "did:web:example.com"
    verification_method = did <> "#ed25519-key"

    document = %{
      "id" => did,
      "verificationMethod" => [
        %{
          "id" => verification_method,
          "type" => "Multikey",
          "controller" => %{id: did},
          "publicKeyMultibase" => multibase
        }
      ],
      "assertionMethod" => [verification_method]
    }

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == "https://example.com/.well-known/did.json"
      {:ok, %{status: 200, body: document, headers: []}}
    end)

    assert {:ok, ^public_key} = DidWeb.resolve_public_key(verification_method, did)
  end

  test "resolve_public_key/2 rejects assertion methods expressed as malformed objects" do
    verification_method = "did:web:example.com#ed25519-key"

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == "https://example.com/.well-known/did.json"

      {:ok,
       %{
         status: 200,
         body: %{
           "id" => "did:web:example.com",
           "assertionMethod" => [%{"id" => 123}]
         },
         headers: []
       }}
    end)

    assert {:error, :unauthorized_verification_method} =
             DidWeb.resolve_public_key(verification_method, nil)
  end

  test "resolve_public_key/2 accepts verification methods expressed as strings but skips non-map entries" do
    did = "did:web:example.com"
    verification_method = did <> "#ed25519-key"

    document = %{
      "id" => did,
      "verificationMethod" => [verification_method],
      "assertionMethod" => [verification_method]
    }

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == "https://example.com/.well-known/did.json"
      {:ok, %{status: 200, body: document, headers: []}}
    end)

    assert {:error, :missing_key} = DidWeb.resolve_public_key(verification_method, nil)
  end

  test "resolve_public_key/1 uses a nil actor id by default" do
    {public_key, _private_key} = Keys.generate_ed25519_keypair()
    multibase = Keys.ed25519_public_key_multibase(public_key)

    did = "did:web:example.com"
    verification_method = did <> "#ed25519-key"

    document = %{
      "id" => did,
      "verificationMethod" => [
        %{
          "id" => verification_method,
          "type" => "Multikey",
          "controller" => did,
          "publicKeyMultibase" => multibase
        }
      ],
      "assertionMethod" => [verification_method]
    }

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == "https://example.com/.well-known/did.json"
      {:ok, %{status: 200, body: document, headers: []}}
    end)

    assert {:ok, ^public_key} = DidWeb.resolve_public_key(verification_method)
  end

  test "resolve_public_key/2 rejects verification methods without did:web identifiers" do
    assert {:error, :invalid_did} = DidWeb.resolve_public_key("https://example.com#key", nil)
    assert {:error, :invalid_did} = DidWeb.resolve_public_key(nil, nil)
  end

  test "resolve_public_key/2 rejects actor ids not present in did documents" do
    {public_key, _private_key} = Keys.generate_ed25519_keypair()
    multibase = Keys.ed25519_public_key_multibase(public_key)

    did = "did:web:example.com"
    verification_method = did <> "#ed25519-key"

    document = %{
      "id" => did,
      "alsoKnownAs" => ["https://example.com/users/someone-else"],
      "verificationMethod" => [
        %{
          "id" => verification_method,
          "type" => "Multikey",
          "controller" => did,
          "publicKeyMultibase" => multibase
        }
      ],
      "assertionMethod" => [verification_method]
    }

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == "https://example.com/.well-known/did.json"
      {:ok, %{status: 200, body: document, headers: []}}
    end)

    assert {:error, :actor_mismatch} =
             DidWeb.resolve_public_key(verification_method, "https://example.com/users/alice")
  end

  test "resolve_public_key/2 rejects verification methods not authorized for assertion" do
    {public_key, _private_key} = Keys.generate_ed25519_keypair()
    multibase = Keys.ed25519_public_key_multibase(public_key)

    did = "did:web:example.com"
    verification_method = did <> "#ed25519-key"

    document = %{
      "id" => did,
      "verificationMethod" => [
        %{
          "id" => verification_method,
          "type" => "Multikey",
          "controller" => did,
          "publicKeyMultibase" => multibase
        }
      ],
      "assertionMethod" => []
    }

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == "https://example.com/.well-known/did.json"
      {:ok, %{status: 200, body: document, headers: []}}
    end)

    assert {:error, :unauthorized_verification_method} =
             DidWeb.resolve_public_key(verification_method, nil)
  end

  test "resolve_public_key/2 returns a missing key error when verification methods are missing" do
    did = "did:web:example.com"
    verification_method = did <> "#ed25519-key"

    document = %{
      "id" => did,
      "assertionMethod" => [verification_method]
    }

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == "https://example.com/.well-known/did.json"
      {:ok, %{status: 200, body: document, headers: []}}
    end)

    assert {:error, :missing_key} = DidWeb.resolve_public_key(verification_method, nil)
  end

  test "resolve_public_key/2 supports assertion methods expressed as objects" do
    {public_key, _private_key} = Keys.generate_ed25519_keypair()
    multibase = Keys.ed25519_public_key_multibase(public_key)

    did = "did:web:example.com"
    verification_method = did <> "#ed25519-key"

    document = %{
      "id" => did,
      "verificationMethod" => [
        %{
          "id" => verification_method,
          "type" => ["Multikey"],
          "controller" => %{"id" => did},
          "publicKeyMultibase" => multibase
        }
      ],
      "assertionMethod" => [%{"id" => verification_method}]
    }

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == "https://example.com/.well-known/did.json"
      {:ok, %{status: 200, body: document, headers: []}}
    end)

    assert {:ok, ^public_key} = DidWeb.resolve_public_key(verification_method, did)
  end

  test "resolve_public_key/2 resolves keys for the local instance did without HTTP" do
    {:ok, actor} = InstanceActor.get_actor()
    did = DidWeb.instance_did()
    verification_method = did <> "#ed25519-key"

    assert {:ok, public_key} = DidWeb.resolve_public_key(verification_method, actor.ap_id)
    assert is_binary(public_key) and byte_size(public_key) == 32
  end

  test "resolve_public_key/2 propagates did fetch errors" do
    verification_method = "did:web:example.com#ed25519-key"

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == "https://example.com/.well-known/did.json"
      {:error, :timeout}
    end)

    assert {:error, :timeout} = DidWeb.resolve_public_key(verification_method, nil)
  end

  test "resolve_public_key/2 returns did_fetch_failed for non-2xx responses or invalid JSON" do
    verification_method = "did:web:example.com#ed25519-key"

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == "https://example.com/.well-known/did.json"
      {:ok, %{status: 404, body: "", headers: []}}
    end)

    assert {:error, :did_fetch_failed} = DidWeb.resolve_public_key(verification_method, nil)

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == "https://example.com/.well-known/did.json"
      {:ok, %{status: 200, body: "not-json", headers: []}}
    end)

    assert {:error, :invalid_json} = DidWeb.resolve_public_key(verification_method, nil)
  end

  test "instance_document/1 builds a did:web document with an assertion method" do
    {_public_key, private_key} = Keys.generate_ed25519_keypair()
    actor = %User{ap_id: "https://example.com/users/alice", ed25519_private_key: private_key}

    assert {:ok, document} = DidWeb.instance_document(actor)
    assert document["id"] == DidWeb.instance_did()
    assert document["alsoKnownAs"] == [actor.ap_id]
    assert is_list(document["verificationMethod"])
    assert is_list(document["assertionMethod"])
  end

  test "instance_document/1 rejects invalid ed25519 keys" do
    actor = %User{ap_id: "https://example.com/users/alice", ed25519_private_key: "short"}
    assert {:error, :invalid_ed25519_key} = DidWeb.instance_document(actor)
  end

  test "actor_matches_did?/2 validates actor aliases for the local instance did" do
    {:ok, actor} = InstanceActor.get_actor()
    did = DidWeb.instance_did()

    assert DidWeb.actor_matches_did?(actor.ap_id, did)
    refute DidWeb.actor_matches_did?("https://example.com/users/mismatch", did)

    refute DidWeb.actor_matches_did?(actor.ap_id, "did:key:z6Mk...")
    refute DidWeb.actor_matches_did?(nil, did)
    refute DidWeb.did_web?(nil)
    refute DidWeb.instance_did?(nil)
  end

  test "did_document_url/1 returns nil for malformed did:web identifiers" do
    assert DidWeb.did_document_url("did:web:") == nil
    assert DidWeb.did_from_url("not-a-url") == nil
  end
end
