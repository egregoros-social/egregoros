defmodule Egregoros.VerifiableCredentials.ReproofTest do
  use ExUnit.Case, async: true

  alias Egregoros.Keys
  alias Egregoros.VerifiableCredentials.Reproof

  @activitystreams_context "https://www.w3.org/ns/activitystreams"
  @credentials_context "https://www.w3.org/ns/credentials/v2"

  test "reproof_document/3 skips documents without proofs" do
    document = %{"@context" => [@credentials_context]}
    {_, private_key} = Keys.generate_ed25519_keypair()

    assert {:skip, :missing_proof} =
             Reproof.reproof_document(document, "did:web:example.com", private_key)
  end

  test "reproof_document/3 returns invalid_document for malformed inputs" do
    assert {:error, :invalid_document} =
             Reproof.reproof_document(:not_a_map, "did:web:example.com", "key")

    assert {:error, :invalid_document} = Reproof.reproof_document(%{}, nil, "key")
    assert {:error, :invalid_document} = Reproof.reproof_document(%{}, "did:web:example.com", nil)
  end

  test "reproof_document/3 skips documents when the context is already normalized" do
    document = %{
      "@context" => [@credentials_context, %{"to" => %{"@id" => "https://example.com/to"}}],
      "proof" => %{}
    }

    {_, private_key} = Keys.generate_ed25519_keypair()

    assert {:skip, :context_unchanged} =
             Reproof.reproof_document(document, "did:web:example.com", private_key)
  end

  test "reproof_document/3 removes activitystreams context, ensures audience mapping, and re-attaches a proof" do
    document = %{
      "@context" => [@activitystreams_context, @credentials_context],
      "id" => "https://example.com/badges/1",
      "type" => ["VerifiableCredential"],
      "issuer" => "did:web:example.com",
      "credentialSubject" => %{"id" => "https://example.com/users/alice"},
      "proof" => %{}
    }

    {_, private_key} = Keys.generate_ed25519_keypair()

    assert {:ok, updated} = Reproof.reproof_document(document, "did:web:example.com", private_key)

    contexts = List.wrap(updated["@context"])
    refute @activitystreams_context in contexts
    assert Enum.any?(contexts, &is_map/1)

    assert %{} = updated["proof"]
    assert updated["proof"]["type"] == "DataIntegrityProof"
    assert updated["proof"]["cryptosuite"] == "eddsa-jcs-2022"
  end

  test "ensure_document/4 skips when a proof is already present and no changes are needed" do
    document = %{
      "@context" => [@credentials_context, %{"to" => %{"@id" => "https://example.com/to"}}],
      "proof" => %{}
    }

    {_, private_key} = Keys.generate_ed25519_keypair()

    assert {:skip, :proof_present} =
             Reproof.ensure_document(document, "did:web:example.com", private_key, [])
  end

  test "ensure_document/4 skips when a proof is present under atom keys" do
    document = %{
      "@context" => [@credentials_context, %{"to" => %{"@id" => "https://example.com/to"}}],
      proof: %{}
    }

    {_, private_key} = Keys.generate_ed25519_keypair()

    assert {:skip, :proof_present} =
             Reproof.ensure_document(document, "did:web:example.com", private_key, [])
  end

  test "ensure_document/4 attaches a proof when none exists" do
    document = %{
      "@context" => [@credentials_context, %{"to" => %{"@id" => "https://example.com/to"}}]
    }

    {_, private_key} = Keys.generate_ed25519_keypair()

    assert {:ok, updated} =
             Reproof.ensure_document(document, "did:web:example.com", private_key, [])

    assert %{} = updated["proof"]
  end

  test "ensure_document/4 preserves created/domain/challenge options when valid" do
    created = "2023-02-24T23:36:38Z"

    document = %{
      "@context" => [@activitystreams_context, @credentials_context],
      "proof" => %{
        "created" => created,
        "domain" => "example.com",
        "challenge" => "abc123"
      }
    }

    {_, private_key} = Keys.generate_ed25519_keypair()

    assert {:ok, updated} =
             Reproof.ensure_document(document, "did:web:example.com", private_key, [])

    assert updated["proof"]["created"] == created
    assert updated["proof"]["domain"] == "example.com"
    assert updated["proof"]["challenge"] == "abc123"
  end

  test "ensure_document/4 ignores invalid created options" do
    document = %{
      "@context" => [@activitystreams_context, @credentials_context],
      "proof" => %{"created" => "not-a-date"}
    }

    {_, private_key} = Keys.generate_ed25519_keypair()

    assert {:ok, updated} =
             Reproof.ensure_document(document, "did:web:example.com", private_key, [])

    refute updated["proof"]["created"] == "not-a-date"
  end

  test "ensure_document/3 uses default options" do
    document = %{
      "@context" => [@credentials_context, %{"to" => %{"@id" => "https://example.com/to"}}]
    }

    {_, private_key} = Keys.generate_ed25519_keypair()

    assert {:ok, updated} = Reproof.ensure_document(document, "did:web:example.com", private_key)
    assert %{} = updated["proof"]
  end

  test "ensure_document/4 re-attaches proofs when forced" do
    document = %{
      "@context" => [@credentials_context, %{"to" => %{"@id" => "https://example.com/to"}}],
      "proof" => %{"verificationMethod" => "did:web:example.com#ed25519-key"}
    }

    {_, private_key} = Keys.generate_ed25519_keypair()

    assert {:ok, updated} =
             Reproof.ensure_document(document, "did:web:example.com", private_key, force: true)

    assert updated["proof"]["verificationMethod"] == "did:web:example.com#ed25519-key"
  end

  test "ensure_document/4 returns an error when the private key is invalid" do
    document = %{
      "@context" => [@credentials_context, %{"to" => %{"@id" => "https://example.com/to"}}]
    }

    assert {:error, :invalid_private_key} =
             Reproof.ensure_document(document, "did:web:example.com", "not-a-private-key", [])
  end

  test "ensure_document/4 returns invalid_document for malformed inputs" do
    assert {:error, :invalid_document} =
             Reproof.ensure_document(:not_a_map, "did:web:example.com", "key", [])

    assert {:error, :invalid_document} =
             Reproof.ensure_document(%{}, nil, "key", [])

    assert {:error, :invalid_document} =
             Reproof.ensure_document(%{}, "did:web:example.com", nil, [])
  end

  test "migrate_document_to_did/4 updates the issuer id and proof verification method" do
    issuer_ap_id = "https://example.com/users/instance"
    did = "did:web:example.com"

    document = %{
      "@context" => [@activitystreams_context, @credentials_context],
      "issuer" => issuer_ap_id,
      "proof" => %{"verificationMethod" => issuer_ap_id <> "#ed25519-key"}
    }

    {_, private_key} = Keys.generate_ed25519_keypair()

    assert {:ok, updated} =
             Reproof.migrate_document_to_did(document, issuer_ap_id, private_key, did)

    assert updated["issuer"] == did
    assert updated["proof"]["verificationMethod"] == did <> "#ed25519-key"
  end

  test "migrate_document_to_did/4 skips documents whose issuer does not match" do
    issuer_ap_id = "https://example.com/users/instance"
    did = "did:web:example.com"

    document = %{
      "@context" => [@credentials_context],
      "issuer" => "https://other.example/users/instance",
      "proof" => %{}
    }

    {_, private_key} = Keys.generate_ed25519_keypair()

    assert {:skip, :issuer_mismatch} =
             Reproof.migrate_document_to_did(document, issuer_ap_id, private_key, did)
  end

  test "migrate_document_to_did/4 returns invalid_document for malformed inputs" do
    assert {:error, :invalid_document} =
             Reproof.migrate_document_to_did(
               :not_a_map,
               "https://example.com/users/instance",
               "key",
               "did:web:example.com"
             )

    assert {:error, :invalid_document} =
             Reproof.migrate_document_to_did(%{}, nil, "key", "did:web:example.com")

    assert {:error, :invalid_document} =
             Reproof.migrate_document_to_did(
               %{},
               "https://example.com/users/instance",
               nil,
               "did:web:example.com"
             )
  end
end
