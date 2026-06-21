defmodule Egregoros.VerifiableCredentials.Reproof do
  @moduledoc """
  Utilities for removing the ActivityStreams context from local verifiable
  credentials, ensuring audience term mappings are present, and regenerating
  their Data Integrity proofs.
  """

  import Ecto.Query, only: [from: 2]

  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Repo
  alias Egregoros.User
  alias Egregoros.Users
  alias Egregoros.VerifiableCredentials.DataIntegrity
  alias Egregoros.VerifiableCredentials.DidWeb
  alias Egregoros.Federation.InstanceActor

  @activitystreams_context "https://www.w3.org/ns/activitystreams"
  @audience_context %{
    "to" => %{"@id" => "https://www.w3.org/ns/activitystreams#to", "@type" => "@id"},
    "cc" => %{"@id" => "https://www.w3.org/ns/activitystreams#cc", "@type" => "@id"},
    "audience" => %{"@id" => "https://www.w3.org/ns/activitystreams#audience", "@type" => "@id"},
    "bto" => %{"@id" => "https://www.w3.org/ns/activitystreams#bto", "@type" => "@id"},
    "bcc" => %{"@id" => "https://www.w3.org/ns/activitystreams#bcc", "@type" => "@id"}
  }

  @type summary :: %{
          updated: non_neg_integer(),
          skipped: non_neg_integer(),
          errors: non_neg_integer()
        }

  @spec reproof_local_credentials(keyword()) :: {:ok, summary()} | {:error, term()}
  def reproof_local_credentials(opts \\ []) when is_list(opts) do
    dry_run = Keyword.get(opts, :dry_run, false)
    limit = Keyword.get(opts, :limit)
    batch_size = Keyword.get(opts, :batch_size, 100)

    query =
      from(o in Object, where: o.type == "VerifiableCredential" and o.local == true)
      |> maybe_limit(limit)

    Repo.transaction(
      fn ->
        Repo.stream(query)
        |> Stream.chunk_every(batch_size)
        |> Enum.reduce(%{updated: 0, skipped: 0, errors: 0}, fn chunk, acc ->
          Enum.reduce(chunk, acc, fn object, acc ->
            case reproof_object(object, dry_run: dry_run) do
              {:ok, _} -> %{acc | updated: acc.updated + 1}
              {:skip, _} -> %{acc | skipped: acc.skipped + 1}
              {:error, _} -> %{acc | errors: acc.errors + 1}
            end
          end)
        end)
      end,
      timeout: :infinity
    )
    |> case do
      {:ok, summary} -> {:ok, summary}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec ensure_local_credentials(keyword()) :: {:ok, summary()} | {:error, term()}
  def ensure_local_credentials(opts \\ []) when is_list(opts) do
    dry_run = Keyword.get(opts, :dry_run, false)
    limit = Keyword.get(opts, :limit)
    batch_size = Keyword.get(opts, :batch_size, 100)
    force = Keyword.get(opts, :force, false)

    query =
      from(o in Object, where: o.type == "VerifiableCredential" and o.local == true)
      |> maybe_limit(limit)

    Repo.transaction(
      fn ->
        Repo.stream(query)
        |> Stream.chunk_every(batch_size)
        |> Enum.reduce(%{updated: 0, skipped: 0, errors: 0}, fn chunk, acc ->
          Enum.reduce(chunk, acc, fn object, acc ->
            case ensure_object(object, dry_run: dry_run, force: force) do
              {:ok, _} -> %{acc | updated: acc.updated + 1}
              {:skip, _} -> %{acc | skipped: acc.skipped + 1}
              {:error, _} -> %{acc | errors: acc.errors + 1}
            end
          end)
        end)
      end,
      timeout: :infinity
    )
    |> case do
      {:ok, summary} -> {:ok, summary}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec reproof_object(Object.t(), keyword()) ::
          {:ok, Object.t() | map()} | {:skip, atom()} | {:error, term()}
  def reproof_object(%Object{} = object, opts \\ []) when is_list(opts) do
    data = object.data || %{}

    case issuer_ap_id(data, object.actor) do
      issuer_ap_id when is_binary(issuer_ap_id) ->
        case issuer_user(issuer_ap_id) do
          {:ok, %User{local: true, ed25519_private_key: private_key} = _issuer}
          when is_binary(private_key) ->
            case reproof_document(data, issuer_ap_id, private_key) do
              {:ok, updated_document} ->
                if Keyword.get(opts, :dry_run, false) do
                  {:ok, updated_document}
                else
                  Objects.update_object(object, %{data: updated_document})
                end

              {:skip, reason} ->
                {:skip, reason}

              {:error, reason} ->
                {:error, reason}
            end

          {:ok, %User{}} ->
            {:skip, :missing_private_key}

          _ ->
            {:skip, :missing_issuer}
        end

      _ ->
        {:skip, :missing_issuer}
    end
  end

  @spec ensure_object(Object.t(), keyword()) ::
          {:ok, Object.t() | map()} | {:skip, atom()} | {:error, term()}
  def ensure_object(%Object{} = object, opts \\ []) when is_list(opts) do
    data = object.data || %{}

    case issuer_ap_id(data, object.actor) do
      issuer_ap_id when is_binary(issuer_ap_id) ->
        case issuer_user(issuer_ap_id) do
          {:ok, %User{local: true, ed25519_private_key: private_key} = _issuer}
          when is_binary(private_key) ->
            case ensure_document(data, issuer_ap_id, private_key, opts) do
              {:ok, updated_document} ->
                if Keyword.get(opts, :dry_run, false) do
                  {:ok, updated_document}
                else
                  Objects.update_object(object, %{data: updated_document})
                end

              {:skip, reason} ->
                {:skip, reason}

              {:error, reason} ->
                {:error, reason}
            end

          {:ok, %User{}} ->
            {:skip, :missing_private_key}

          _ ->
            {:skip, :missing_issuer}
        end

      _ ->
        {:skip, :missing_issuer}
    end
  end

  @spec reproof_document(map(), binary(), binary()) ::
          {:ok, map()} | {:skip, atom()} | {:error, term()}
  def reproof_document(document, issuer_ap_id, private_key)
      when is_map(document) and is_binary(issuer_ap_id) and is_binary(private_key) do
    if proof_present?(document) do
      {updated_context, changed?} = normalize_context(document["@context"])

      cond do
        not changed? ->
          {:skip, :context_unchanged}

        updated_context == [] ->
          {:error, :invalid_context}

        true ->
          unsigned =
            document
            |> Map.put("@context", updated_context)
            |> drop_proof()

          proof_opts = build_proof_opts(document, issuer_ap_id)
          DataIntegrity.attach_proof(unsigned, private_key, proof_opts)
      end
    else
      {:skip, :missing_proof}
    end
  end

  def reproof_document(_document, _issuer_ap_id, _private_key), do: {:error, :invalid_document}

  @spec ensure_document(map(), binary(), binary(), keyword()) ::
          {:ok, map()} | {:skip, atom()} | {:error, term()}
  def ensure_document(document, issuer_ap_id, private_key, opts \\ [])

  def ensure_document(document, issuer_ap_id, private_key, opts)
      when is_map(document) and is_binary(issuer_ap_id) and is_binary(private_key) and
             is_list(opts) do
    {updated_context, changed?} = normalize_context(document["@context"])
    force = Keyword.get(opts, :force, false)

    if changed? and updated_context == [] do
      {:error, :invalid_context}
    else
      document =
        if changed? do
          Map.put(document, "@context", updated_context)
        else
          document
        end

      proof_opts = build_proof_opts(document, issuer_ap_id)

      cond do
        proof_present?(document) and not changed? and not force ->
          {:skip, :proof_present}

        true ->
          document
          |> drop_proof()
          |> DataIntegrity.attach_proof(private_key, proof_opts)
      end
    end
  end

  def ensure_document(_document, _issuer_ap_id, _private_key, _opts),
    do: {:error, :invalid_document}

  @spec migrate_local_credentials_to_did(keyword()) :: {:ok, summary()} | {:error, term()}
  def migrate_local_credentials_to_did(opts \\ []) when is_list(opts) do
    dry_run = Keyword.get(opts, :dry_run, false)
    limit = Keyword.get(opts, :limit)
    batch_size = Keyword.get(opts, :batch_size, 100)

    query =
      from(o in Object, where: o.type == "VerifiableCredential" and o.local == true)
      |> maybe_limit(limit)

    Repo.transaction(
      fn ->
        Repo.stream(query)
        |> Stream.chunk_every(batch_size)
        |> Enum.reduce(%{updated: 0, skipped: 0, errors: 0}, fn chunk, acc ->
          Enum.reduce(chunk, acc, fn object, acc ->
            case migrate_object_to_did(object, dry_run: dry_run) do
              {:ok, _} -> %{acc | updated: acc.updated + 1}
              {:skip, _} -> %{acc | skipped: acc.skipped + 1}
              {:error, _} -> %{acc | errors: acc.errors + 1}
            end
          end)
        end)
      end,
      timeout: :infinity
    )
    |> case do
      {:ok, summary} -> {:ok, summary}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec migrate_object_to_did(Object.t(), keyword()) ::
          {:ok, Object.t() | map()} | {:skip, atom()} | {:error, term()}
  def migrate_object_to_did(%Object{} = object, opts \\ []) when is_list(opts) do
    data = object.data || %{}

    with {:ok, %User{} = issuer} <- InstanceActor.get_actor(),
         did when is_binary(did) <- DidWeb.instance_did(),
         true <- did != "" do
      issuer_id = issuer_ap_id(data, object.actor)

      cond do
        not is_binary(issuer_id) ->
          {:skip, :missing_issuer}

        issuer_id != issuer.ap_id and issuer_id != did ->
          {:skip, :issuer_mismatch}

        true ->
          case migrate_document_to_did(data, issuer.ap_id, issuer.ed25519_private_key, did) do
            {:ok, updated_document} ->
              if Keyword.get(opts, :dry_run, false) do
                {:ok, updated_document}
              else
                Objects.update_object(object, %{data: updated_document})
              end

            {:skip, reason} ->
              {:skip, reason}

            {:error, reason} ->
              {:error, reason}
          end
      end
    else
      _ -> {:error, :missing_issuer}
    end
  end

  @spec migrate_document_to_did(map(), binary(), binary(), binary()) ::
          {:ok, map()} | {:skip, atom()} | {:error, term()}
  def migrate_document_to_did(document, issuer_ap_id, private_key, did)
      when is_map(document) and is_binary(issuer_ap_id) and is_binary(private_key) and
             is_binary(did) do
    {updated_context, changed?} = normalize_context(document["@context"])

    if changed? and updated_context == [] do
      {:error, :invalid_context}
    else
      issuer_id = issuer_ap_id(document, issuer_ap_id)

      cond do
        not is_binary(issuer_id) ->
          {:error, :missing_issuer}

        issuer_id != issuer_ap_id and issuer_id != did ->
          {:skip, :issuer_mismatch}

        true ->
          document =
            document
            |> Map.put("@context", updated_context)
            |> Map.put("issuer", did)
            |> drop_proof()

          proof_opts =
            build_proof_opts(document, did)
            |> Map.put("verificationMethod", did <> "#ed25519-key")

          DataIntegrity.attach_proof(document, private_key, proof_opts)
      end
    end
  end

  def migrate_document_to_did(_document, _issuer_ap_id, _private_key, _did),
    do: {:error, :invalid_document}

  defp maybe_limit(query, limit) when is_integer(limit) and limit > 0 do
    from(o in query, limit: ^limit)
  end

  defp maybe_limit(query, _limit), do: query

  defp issuer_ap_id(%{"issuer" => %{"id" => id}}, _actor) when is_binary(id), do: id
  defp issuer_ap_id(%{issuer: %{id: id}}, _actor) when is_binary(id), do: id
  defp issuer_ap_id(%{"issuer" => id}, _actor) when is_binary(id), do: id
  defp issuer_ap_id(%{issuer: id}, _actor) when is_binary(id), do: id
  defp issuer_ap_id(_data, actor) when is_binary(actor), do: actor
  defp issuer_ap_id(_data, _actor), do: nil

  defp issuer_user(issuer_ap_id) when is_binary(issuer_ap_id) do
    case Users.get_by_ap_id(issuer_ap_id) do
      %User{} = user ->
        {:ok, user}

      _ ->
        if DidWeb.instance_did?(issuer_ap_id) do
          InstanceActor.get_actor()
        else
          {:error, :missing_issuer}
        end
    end
  end

  defp issuer_user(_issuer_ap_id), do: {:error, :missing_issuer}

  defp remove_activitystreams_context(context) do
    contexts = List.wrap(context)
    updated = Enum.reject(contexts, &(&1 == @activitystreams_context))
    {updated, updated != contexts}
  end

  defp normalize_context(context) do
    {contexts, removed?} = remove_activitystreams_context(context)
    has_mapping? = Enum.any?(List.wrap(contexts), &audience_context?/1)

    if has_mapping? do
      {contexts, removed?}
    else
      {contexts ++ [@audience_context], true}
    end
  end

  defp audience_context?(%{} = context) do
    Map.has_key?(context, "to")
  end

  defp audience_context?(_context), do: false

  defp drop_proof(%{} = document) do
    Map.drop(document, ["proof", :proof])
  end

  defp proof_present?(%{"proof" => %{} = _proof}), do: true
  defp proof_present?(%{proof: %{} = _proof}), do: true
  defp proof_present?(_document), do: false

  defp build_proof_opts(document, issuer_ap_id) do
    proof = Map.get(document, "proof") || Map.get(document, :proof)

    verification_method =
      proof_string(proof, "verificationMethod") ||
        DidWeb.verification_method_id(issuer_ap_id) ||
        String.trim(issuer_ap_id) <> "#ed25519-key"

    proof_purpose = proof_string(proof, "proofPurpose") || "assertionMethod"

    %{}
    |> Map.put("verificationMethod", verification_method)
    |> Map.put("proofPurpose", proof_purpose)
    |> maybe_put_opt("created", proof_string(proof, "created"), &valid_datetime?/1)
    |> maybe_put_opt("domain", proof_string(proof, "domain"))
    |> maybe_put_opt("challenge", proof_string(proof, "challenge"))
  end

  defp proof_string(%{} = proof, key) when is_binary(key) do
    atom_key =
      case key do
        "verificationMethod" -> :verificationMethod
        "proofPurpose" -> :proofPurpose
        "created" -> :created
        "domain" -> :domain
        "challenge" -> :challenge
        _ -> nil
      end

    value =
      case atom_key do
        nil -> Map.get(proof, key)
        atom -> Map.get(proof, key) || Map.get(proof, atom)
      end

    case value do
      value when is_binary(value) ->
        trimmed = String.trim(value)
        if trimmed == "", do: nil, else: trimmed

      _ ->
        nil
    end
  end

  defp proof_string(_proof, _key), do: nil

  defp maybe_put_opt(map, _key, nil, _validator), do: map

  defp maybe_put_opt(map, key, value, validator)
       when is_binary(key) and is_function(validator, 1) do
    if validator.(value) do
      Map.put(map, key, value)
    else
      map
    end
  end

  defp maybe_put_opt(map, _key, _value, _validator), do: map

  defp maybe_put_opt(map, _key, nil), do: map

  defp maybe_put_opt(map, key, value) when is_binary(key) and is_binary(value) do
    Map.put(map, key, value)
  end

  defp maybe_put_opt(map, _key, _value), do: map

  defp valid_datetime?(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, _datetime, _offset} -> true
      _ -> false
    end
  end

  defp valid_datetime?(_value), do: false
end
