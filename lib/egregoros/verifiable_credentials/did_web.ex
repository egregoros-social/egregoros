defmodule Egregoros.VerifiableCredentials.DidWeb do
  @moduledoc """
  Helpers for working with did:web identifiers and documents.
  """

  alias Egregoros.Domain
  alias Egregoros.HTTP
  alias Egregoros.Keys
  alias Egregoros.User
  alias Egregoros.Federation.InstanceActor
  alias EgregorosWeb.Endpoint

  @did_prefix "did:web:"
  @did_context "https://www.w3.org/ns/did/v1"
  @data_integrity_context "https://w3id.org/security/data-integrity/v2"
  @key_fragment "#ed25519-key"

  @spec instance_did() :: binary() | nil
  def instance_did do
    Endpoint.url()
    |> did_from_url()
  end

  @spec instance_did?(term()) :: boolean()
  def instance_did?(id) when is_binary(id) do
    id == instance_did()
  end

  def instance_did?(_id), do: false

  @spec did_web?(term()) :: boolean()
  def did_web?(id) when is_binary(id) do
    String.starts_with?(id, @did_prefix)
  end

  def did_web?(_id), do: false

  @spec did_from_url(binary()) :: binary() | nil
  def did_from_url(url) when is_binary(url) do
    with %URI{} = uri <- URI.parse(url),
         domain when is_binary(domain) and domain != "" <- Domain.from_uri(uri) || uri.host do
      @did_prefix <> domain
    else
      _ -> nil
    end
  end

  def did_from_url(_url), do: nil

  @spec did_from_verification_method(binary()) :: binary() | nil
  def did_from_verification_method(verification_method) when is_binary(verification_method) do
    verification_method
    |> String.split("#", parts: 2)
    |> List.first()
    |> case do
      did when is_binary(did) ->
        if did_web?(did), do: did, else: nil

      _ ->
        nil
    end
  end

  def did_from_verification_method(_verification_method), do: nil

  @spec verification_method_id(binary()) :: binary() | nil
  def verification_method_id(issuer_id) when is_binary(issuer_id) do
    issuer_id = String.trim(issuer_id)

    if issuer_id == "" do
      nil
    else
      issuer_id <> @key_fragment
    end
  end

  def verification_method_id(_issuer_id), do: nil

  @spec public_key_multibase(binary()) :: binary() | nil
  def public_key_multibase(public_key) when is_binary(public_key) do
    Keys.ed25519_public_key_multibase(public_key)
  end

  def public_key_multibase(_public_key), do: nil

  @spec instance_document(User.t()) :: {:ok, map()} | {:error, atom()}
  def instance_document(%User{} = actor) do
    with did when is_binary(did) <- instance_did(),
         true <- did != "" || {:error, :invalid_did},
         {:ok, public_key} <- Keys.ed25519_public_key_from_private_key(actor.ed25519_private_key),
         multibase when is_binary(multibase) <- Keys.ed25519_public_key_multibase(public_key) do
      method_id = did <> @key_fragment

      {:ok,
       %{
         "@context" => [@did_context, @data_integrity_context],
         "id" => did,
         "alsoKnownAs" => [actor.ap_id],
         "verificationMethod" => [
           %{
             "id" => method_id,
             "type" => "Multikey",
             "controller" => did,
             "publicKeyMultibase" => multibase
           }
         ],
         "assertionMethod" => [method_id]
       }}
    else
      nil -> {:error, :invalid_did}
      {:error, _} = error -> error
      _ -> {:error, :invalid_key}
    end
  end

  def instance_document(_actor), do: {:error, :invalid_actor}

  @spec resolve_public_key(binary(), binary() | nil) :: {:ok, binary()} | {:error, atom()}
  def resolve_public_key(verification_method, actor_ap_id \\ nil)

  def resolve_public_key(verification_method, actor_ap_id)
      when is_binary(verification_method) do
    with did when is_binary(did) <- did_from_verification_method(verification_method),
         {:ok, document} <- fetch_document(did),
         :ok <- validate_document_id(document, did),
         :ok <- validate_actor_alias(document, actor_ap_id, did),
         :ok <- validate_assertion_method(document, verification_method),
         {:ok, public_key} <- extract_ed25519_public_key(document, verification_method, did) do
      {:ok, public_key}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_did}
    end
  end

  def resolve_public_key(_verification_method, _actor_ap_id), do: {:error, :invalid_did}

  @spec actor_matches_did?(binary(), binary()) :: boolean()
  def actor_matches_did?(actor_ap_id, did) when is_binary(actor_ap_id) and is_binary(did) do
    case fetch_document(did) do
      {:ok, document} ->
        actor_ap_id = String.trim(actor_ap_id)
        aliases = document |> Map.get("alsoKnownAs", []) |> List.wrap()
        actor_ap_id != "" and actor_ap_id in aliases

      _ ->
        false
    end
  end

  def actor_matches_did?(_actor_ap_id, _did), do: false

  @spec did_document_url(binary()) :: binary() | nil
  def did_document_url(did) when is_binary(did) do
    case String.trim(did) do
      "" ->
        nil

      did ->
        case String.split(did, @did_prefix, parts: 2) do
          ["", rest] ->
            segments = String.split(rest, ":", trim: true)

            case segments do
              [domain | path_segments] ->
                {domain, path_segments} =
                  case path_segments do
                    [port | rest_segments] ->
                      if port =~ ~r/^\d+$/ do
                        {domain <> ":" <> port, rest_segments}
                      else
                        {domain, path_segments}
                      end

                    _ ->
                      {domain, path_segments}
                  end

                path =
                  case path_segments do
                    [] -> "/.well-known/did.json"
                    _ -> "/" <> Enum.join(path_segments, "/") <> "/did.json"
                  end

                "https://" <> domain <> path

              _ ->
                nil
            end

          _ ->
            nil
        end
    end
  end

  def did_document_url(_did), do: nil

  @spec did_base_url(binary()) :: binary() | nil
  def did_base_url(did) when is_binary(did) do
    did
    |> did_document_url()
    |> document_base_url()
  end

  def did_base_url(_did), do: nil

  defp document_base_url(url) when is_binary(url) do
    url = String.trim(url)

    cond do
      url == "" ->
        nil

      String.ends_with?(url, "/.well-known/did.json") ->
        String.replace_suffix(url, "/.well-known/did.json", "")

      String.ends_with?(url, "/did.json") ->
        String.replace_suffix(url, "/did.json", "")

      true ->
        url
    end
  end

  defp document_base_url(_url), do: nil

  defp fetch_document(did) when is_binary(did) do
    cond do
      instance_did?(did) ->
        with {:ok, actor} <- InstanceActor.get_actor() do
          instance_document(actor)
        end

      true ->
        with url when is_binary(url) <- did_document_url(did),
             {:ok, %{status: status, body: body}} when status in 200..299 <-
               HTTP.get(url, [{"accept", "application/did+ld+json, application/did+json"}]),
             {:ok, %{} = document} <- decode_json(body) do
          {:ok, document}
        else
          {:error, _} = error -> error
          _ -> {:error, :did_fetch_failed}
        end
    end
  end

  defp fetch_document(_did), do: {:error, :invalid_did}

  defp decode_json(body) when is_map(body), do: {:ok, body}

  defp decode_json(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{} = decoded} -> {:ok, decoded}
      _ -> {:error, :invalid_json}
    end
  end

  defp decode_json(_body), do: {:error, :invalid_json}

  defp validate_document_id(%{} = document, did) when is_binary(did) do
    case Map.get(document, "id") do
      ^did -> :ok
      _ -> {:error, :invalid_did_document}
    end
  end

  defp validate_document_id(_document, _did), do: {:error, :invalid_did_document}

  defp validate_actor_alias(_document, nil, _did), do: :ok

  defp validate_actor_alias(document, actor_ap_id, did)
       when is_map(document) and is_binary(actor_ap_id) and is_binary(did) do
    actor_ap_id = String.trim(actor_ap_id)

    cond do
      actor_ap_id == "" ->
        {:error, :invalid_actor}

      actor_ap_id == did ->
        :ok

      true ->
        aliases = document |> Map.get("alsoKnownAs", []) |> List.wrap()

        if actor_ap_id in aliases do
          :ok
        else
          {:error, :actor_mismatch}
        end
    end
  end

  defp validate_actor_alias(_document, _actor_ap_id, _did), do: {:error, :invalid_actor}

  defp validate_assertion_method(document, verification_method) do
    assertion_method =
      Map.get(document, "assertionMethod") || Map.get(document, :assertionMethod)

    candidates = id_variants(verification_method)

    if candidates == MapSet.new() do
      {:error, :invalid_verification_method}
    else
      assertion_method
      |> List.wrap()
      |> Enum.find_value(fn entry ->
        case entry do
          %{} = method ->
            with {:ok, method_id} <- method_id(method),
                 false <- MapSet.disjoint?(id_variants(method_id), candidates) do
              true
            else
              _ -> nil
            end

          id when is_binary(id) ->
            if MapSet.member?(candidates, String.trim(id)), do: true, else: nil

          _ ->
            nil
        end
      end)
      |> case do
        true -> :ok
        _ -> {:error, :unauthorized_verification_method}
      end
    end
  end

  defp extract_ed25519_public_key(%{} = document, verification_method, did)
       when is_binary(verification_method) and is_binary(did) do
    verification_methods =
      Map.get(document, "verificationMethod") || Map.get(document, :verificationMethod)

    candidates = id_variants(verification_method)

    verification_methods
    |> List.wrap()
    |> Enum.find_value(fn method ->
      with {:ok, method_id} <- method_id(method),
           false <- MapSet.disjoint?(id_variants(method_id), candidates),
           true <- controller_matches?(method, did),
           {:ok, public_key} <- ed25519_public_key_from_method(method) do
        public_key
      else
        _ -> nil
      end
    end)
    |> case do
      nil -> {:error, :missing_key}
      public_key -> {:ok, public_key}
    end
  end

  defp extract_ed25519_public_key(_document, _verification_method, _did),
    do: {:error, :invalid_verification_method}

  defp method_id(%{} = method) do
    case Map.get(method, "id") || Map.get(method, :id) do
      id when is_binary(id) -> {:ok, id}
      _ -> {:error, :invalid_id}
    end
  end

  defp method_id(id) when is_binary(id), do: {:ok, id}
  defp method_id(_method), do: {:error, :invalid_id}

  defp controller_matches?(%{} = method, did) do
    controller = Map.get(method, "controller") || Map.get(method, :controller)

    case controller do
      value when is_binary(value) -> String.trim(value) == did
      %{"id" => id} when is_binary(id) -> String.trim(id) == did
      %{id: id} when is_binary(id) -> String.trim(id) == did
      _ -> false
    end
  end

  defp controller_matches?(_method, _did), do: false

  defp ed25519_public_key_from_method(%{} = method) do
    type = Map.get(method, "type") || Map.get(method, :type)

    if multikey_type?(type) do
      case Map.get(method, "publicKeyMultibase") || Map.get(method, :publicKeyMultibase) do
        multibase when is_binary(multibase) -> Keys.ed25519_public_key_from_multibase(multibase)
        _ -> {:error, :invalid_key}
      end
    else
      {:error, :invalid_key_type}
    end
  end

  defp ed25519_public_key_from_method(_method), do: {:error, :invalid_key}

  defp multikey_type?("Multikey"), do: true
  defp multikey_type?(types) when is_list(types), do: "Multikey" in types
  defp multikey_type?(_type), do: false

  defp id_variants(id) when is_binary(id) do
    id = String.trim(id)

    if id == "" do
      MapSet.new()
    else
      variants = [id]

      variants =
        if String.starts_with?(id, "#") do
          fragment = String.trim_leading(id, "#")
          if fragment == "", do: variants, else: variants ++ [fragment]
        else
          case String.split(id, "#", parts: 2) do
            [_base, fragment] when fragment != "" -> variants ++ ["#" <> fragment, fragment]
            _ -> variants
          end
        end

      MapSet.new(variants)
    end
  end

  defp id_variants(_id), do: MapSet.new()
end
