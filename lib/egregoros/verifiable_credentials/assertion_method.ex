defmodule Egregoros.VerifiableCredentials.AssertionMethod do
  @moduledoc """
  Helpers for working with ActivityPub assertionMethod values.
  """

  alias Egregoros.Keys

  @spec from_ed25519_public_key(binary(), binary()) :: {:ok, list()} | {:error, atom()}
  def from_ed25519_public_key(ap_id, public_key)
      when is_binary(ap_id) and is_binary(public_key) do
    case Keys.ed25519_public_key_multibase(public_key) do
      multibase when is_binary(multibase) ->
        {:ok,
         [
           %{
             "id" => ap_id <> "#ed25519-key",
             "type" => "Multikey",
             "controller" => ap_id,
             "publicKeyMultibase" => multibase
           }
         ]}

      _ ->
        {:error, :invalid_ed25519_key}
    end
  end

  def from_ed25519_public_key(_ap_id, _public_key), do: {:error, :invalid_ed25519_key}

  @spec from_ed25519_private_key(binary(), binary()) :: {:ok, list()} | {:error, atom()}
  def from_ed25519_private_key(ap_id, private_key)
      when is_binary(ap_id) and is_binary(private_key) do
    with {:ok, public_key} <- Keys.ed25519_public_key_from_private_key(private_key) do
      from_ed25519_public_key(ap_id, public_key)
    end
  end

  def from_ed25519_private_key(_ap_id, _private_key), do: {:error, :invalid_ed25519_key}

  @spec find_ed25519_public_key(term(), binary(), binary()) :: {:ok, binary()} | {:error, atom()}
  def find_ed25519_public_key(assertion_method, verification_method, actor_ap_id)
      when is_binary(verification_method) and is_binary(actor_ap_id) do
    actor_ap_id = String.trim(actor_ap_id)

    with true <- actor_ap_id != "" || {:error, :invalid_actor},
         :ok <- validate_verification_method(verification_method, actor_ap_id) do
      candidates = id_variants(verification_method)

      if MapSet.size(candidates) == 0 do
        {:error, :invalid_verification_method}
      else
        assertion_method
        |> List.wrap()
        |> Enum.find_value(fn method ->
          with true <- controller_matches?(method, actor_ap_id),
               {:ok, method_id} <- method_id(method),
               true <- method_id_matches_actor?(method_id, actor_ap_id),
               false <- MapSet.disjoint?(id_variants(method_id), candidates),
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
    else
      {:error, _} = error -> error
      false -> {:error, :invalid_actor}
    end
  end

  def find_ed25519_public_key(_assertion_method, _verification_method, _actor_ap_id),
    do: {:error, :invalid_verification_method}

  def find_ed25519_public_key(_assertion_method, _verification_method),
    do: {:error, :invalid_actor}

  defp method_id(%{} = method) do
    case Map.get(method, "id") || Map.get(method, :id) do
      id when is_binary(id) -> {:ok, id}
      _ -> {:error, :invalid_id}
    end
  end

  defp method_id(id) when is_binary(id), do: {:ok, id}
  defp method_id(_method), do: {:error, :invalid_id}

  defp controller_matches?(%{} = method, actor_ap_id) do
    controller = Map.get(method, "controller") || Map.get(method, :controller)

    case controller do
      value when is_binary(value) -> String.trim(value) == actor_ap_id
      %{"id" => id} when is_binary(id) -> String.trim(id) == actor_ap_id
      %{id: id} when is_binary(id) -> String.trim(id) == actor_ap_id
      _ -> false
    end
  end

  defp controller_matches?(_method, _actor_ap_id), do: false

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

  defp validate_verification_method(verification_method, actor_ap_id) do
    verification_method = String.trim(verification_method)

    cond do
      verification_method == "" ->
        {:error, :invalid_verification_method}

      absolute_uri?(verification_method) ->
        base = String.split(verification_method, "#", parts: 2) |> List.first()

        if base == actor_ap_id do
          :ok
        else
          {:error, :verification_method_mismatch}
        end

      true ->
        :ok
    end
  end

  defp method_id_matches_actor?(method_id, actor_ap_id) when is_binary(method_id) do
    method_id = String.trim(method_id)

    cond do
      method_id == "" ->
        false

      absolute_uri?(method_id) ->
        base = String.split(method_id, "#", parts: 2) |> List.first()
        base == actor_ap_id

      true ->
        true
    end
  end

  defp method_id_matches_actor?(_method_id, _actor_ap_id), do: false

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

  defp absolute_uri?(id) when is_binary(id) do
    case URI.parse(id) do
      %URI{scheme: nil} -> false
      %URI{} -> true
    end
  end

  defp absolute_uri?(_id), do: false
end
