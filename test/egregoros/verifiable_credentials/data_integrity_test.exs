defmodule Egregoros.VerifiableCredentials.DataIntegrityTest do
  use ExUnit.Case, async: true

  alias Egregoros.Keys
  alias Egregoros.VerifiableCredentials.DataIntegrity

  @public_key_multibase "z6MkrJVnaZkeFzdQyMZu1cgjg7k1pZZ6pvBQ7XJPt4swbTQ2"
  @private_key_hex "C96EF9EA10C5E414C471723AFF9DE72C35FA5B70FAE97E8832ECAC7D2E2B8ED6"
  @verification_method "did:key:z6MkrJVnaZkeFzdQyMZu1cgjg7k1pZZ6pvBQ7XJPt4swbTQ2#z6MkrJVnaZkeFzdQyMZu1cgjg7k1pZZ6pvBQ7XJPt4swbTQ2"
  @proof_purpose "assertionMethod"
  @created "2023-02-24T23:36:38Z"
  @expected_proof_value "z2HnFSSPPBzR36zdDgK8PbEHeXbR56YF24jwMpt3R1eHXQzJDMWS93FCzpvJpwTWd3GAVFuUfjoJdcnTMuVor51aX"

  test "attach_proof matches the eddsa-jcs-2022 test vector" do
    unsigned = fixture!("vc_di_eddsa_unsigned.json")
    private_key = Base.decode16!(@private_key_hex, case: :mixed)

    assert {:ok, signed} =
             DataIntegrity.attach_proof(unsigned, private_key, %{
               "verificationMethod" => @verification_method,
               "proofPurpose" => @proof_purpose,
               "created" => @created
             })

    proof = signed["proof"]
    assert proof["proofValue"] == @expected_proof_value
    assert proof["type"] == "DataIntegrityProof"
    assert proof["cryptosuite"] == "eddsa-jcs-2022"
    assert proof["@context"] == unsigned["@context"]
  end

  test "attach_proof rejects documents that already have a proof" do
    unsigned = fixture!("vc_di_eddsa_unsigned.json")
    private_key = Base.decode16!(@private_key_hex, case: :mixed)

    assert {:error, :proof_already_present} =
             DataIntegrity.attach_proof(Map.put(unsigned, "proof", %{}), private_key, %{
               "verificationMethod" => @verification_method,
               "proofPurpose" => @proof_purpose
             })
  end

  test "attach_proof rejects invalid proof options" do
    unsigned = fixture!("vc_di_eddsa_unsigned.json")
    private_key = Base.decode16!(@private_key_hex, case: :mixed)

    assert {:error, :invalid_proof_options} =
             DataIntegrity.attach_proof(unsigned, private_key, %{
               "verificationMethod" => @verification_method
             })

    assert {:error, :invalid_proof_options} =
             DataIntegrity.attach_proof(unsigned, private_key, %{
               "verificationMethod" => "",
               "proofPurpose" => @proof_purpose
             })
  end

  test "attach_proof rejects invalid domain and challenge options" do
    unsigned = fixture!("vc_di_eddsa_unsigned.json")
    private_key = Base.decode16!(@private_key_hex, case: :mixed)

    assert {:error, :invalid_domain} =
             DataIntegrity.attach_proof(unsigned, private_key, %{
               "verificationMethod" => @verification_method,
               "proofPurpose" => @proof_purpose,
               "domain" => ""
             })

    assert {:error, :invalid_challenge} =
             DataIntegrity.attach_proof(unsigned, private_key, %{
               "verificationMethod" => @verification_method,
               "proofPurpose" => @proof_purpose,
               "challenge" => "  "
             })
  end

  test "attach_proof rejects invalid keys and documents" do
    unsigned = fixture!("vc_di_eddsa_unsigned.json")

    assert {:error, :invalid_private_key} =
             DataIntegrity.attach_proof(unsigned, "short", %{
               "verificationMethod" => @verification_method,
               "proofPurpose" => @proof_purpose
             })

    assert {:error, :invalid_document} =
             DataIntegrity.attach_proof(%URI{}, <<0::256>>, %{
               "verificationMethod" => @verification_method,
               "proofPurpose" => @proof_purpose
             })

    assert {:error, :invalid_document} =
             DataIntegrity.attach_proof([:not_a_map], <<0::256>>, %{
               "verificationMethod" => @verification_method,
               "proofPurpose" => @proof_purpose
             })
  end

  test "attach_proof rejects invalid JSON" do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)

    doc = %{"id" => "https://example.com", "nested" => %{__struct__: :not_allowed}}

    assert {:error, :invalid_json} =
             DataIntegrity.attach_proof(doc, private_key, %{
               "verificationMethod" => @verification_method,
               "proofPurpose" => @proof_purpose,
               "created" => @created
             })

    assert {:error, :invalid_document} = DataIntegrity.verify_proof(:not_a_map, public_key)
    assert {:error, :invalid_public_key} = DataIntegrity.verify_proof(%{}, "bad_key")
  end

  test "attach_proof rejects invalid JSON keys" do
    {_public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)

    doc = %{"id" => "https://example.com", 123 => "bad-key-type"}

    assert {:error, :invalid_json_key} =
             DataIntegrity.attach_proof(doc, private_key, %{
               "verificationMethod" => @verification_method,
               "proofPurpose" => @proof_purpose,
               "created" => @created
             })
  end

  test "attach_proof signs and verifies documents with float values" do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)

    doc = %{
      "@context" => ["https://www.w3.org/ns/credentials/v2"],
      "id" => "https://example.com/credentials/1",
      "values" => [0.0, 3.14159, -0.0, 1.0e22, 1.0e-7]
    }

    assert {:ok, signed} =
             DataIntegrity.attach_proof(doc, private_key, %{
               "verificationMethod" => @verification_method,
               "proofPurpose" => @proof_purpose,
               "created" => @created
             })

    assert {:ok, true} = DataIntegrity.verify_proof(signed, public_key)
  end

  test "verify_proof validates the eddsa-jcs-2022 test vector" do
    signed = fixture!("vc_di_eddsa_signed.json")
    {:ok, public_key} = Keys.ed25519_public_key_from_multibase(@public_key_multibase)

    assert {:ok, true} = DataIntegrity.verify_proof(signed, public_key)
  end

  test "verify_proof returns false for tampered content" do
    signed = fixture!("vc_di_eddsa_signed.json")
    {:ok, public_key} = Keys.ed25519_public_key_from_multibase(@public_key_multibase)

    tampered = put_in(signed, ["credentialSubject", "alumniOf"], "Tampered")

    assert {:ok, false} = DataIntegrity.verify_proof(tampered, public_key)
  end

  test "verify_proof rejects missing or invalid proof entries" do
    unsigned = fixture!("vc_di_eddsa_unsigned.json")
    {:ok, public_key} = Keys.ed25519_public_key_from_multibase(@public_key_multibase)

    assert {:error, :missing_proof} = DataIntegrity.verify_proof(unsigned, public_key)

    assert {:error, :invalid_proof} =
             DataIntegrity.verify_proof(Map.put(unsigned, "proof", "not-a-map"), public_key)
  end

  test "verify_proof rejects unsupported proof types and malformed proof values" do
    signed = fixture!("vc_di_eddsa_signed.json")
    {:ok, public_key} = Keys.ed25519_public_key_from_multibase(@public_key_multibase)

    unsupported =
      put_in(signed, ["proof", "type"], "SomethingElse")

    assert {:error, :unsupported_cryptosuite} =
             DataIntegrity.verify_proof(unsupported, public_key)

    malformed =
      put_in(signed, ["proof", "proofValue"], "abc")

    assert {:error, :invalid_proof_value} = DataIntegrity.verify_proof(malformed, public_key)
  end

  test "verify_proof rejects context mismatch" do
    signed = fixture!("vc_di_eddsa_signed.json")
    {:ok, public_key} = Keys.ed25519_public_key_from_multibase(@public_key_multibase)

    mismatch = Map.update!(signed, "@context", fn [first | rest] -> rest ++ [first] end)

    assert {:error, :invalid_context} = DataIntegrity.verify_proof(mismatch, public_key)
  end

  test "attach_proof rejects invalid created value" do
    unsigned = fixture!("vc_di_eddsa_unsigned.json")
    private_key = Base.decode16!(@private_key_hex, case: :mixed)

    assert {:error, :invalid_created} =
             DataIntegrity.attach_proof(unsigned, private_key, %{
               "verificationMethod" => @verification_method,
               "proofPurpose" => @proof_purpose,
               "created" => "not-a-date"
             })
  end

  test "attach_proof supports keyword and atom option keys" do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    unsigned = fixture!("vc_di_eddsa_unsigned.json")

    assert {:ok, signed} =
             DataIntegrity.attach_proof(unsigned, private_key,
               verification_method: @verification_method,
               proof_purpose: @proof_purpose,
               created: @created
             )

    assert {:ok, true} = DataIntegrity.verify_proof(signed, public_key)

    assert {:ok, signed2} =
             DataIntegrity.attach_proof(unsigned, private_key, %{
               verification_method: @verification_method,
               proof_purpose: @proof_purpose
             })

    assert is_binary(signed2["proof"]["created"])
    assert {:ok, true} = DataIntegrity.verify_proof(signed2, public_key)
  end

  defp fixture!(name) do
    "test/fixtures"
    |> Path.join(name)
    |> File.read!()
    |> Jason.decode!()
  end
end
