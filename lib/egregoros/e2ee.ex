defmodule Egregoros.E2EE do
  import Ecto.Query, only: [from: 2]

  alias Egregoros.E2EE.Key
  alias Egregoros.E2EE.KeyWrapper
  alias Egregoros.Repo
  alias Egregoros.User

  def get_active_key(%User{} = user) do
    from(k in Key, where: k.user_id == ^user.id and k.active, limit: 1)
    |> Repo.one()
  end

  def list_active_keys(%User{} = user) do
    from(k in Key, where: k.user_id == ^user.id and k.active, order_by: [desc: k.inserted_at])
    |> Repo.all()
  end

  def list_wrappers(%User{} = user, kid) when is_binary(kid) do
    from(w in KeyWrapper,
      where: w.user_id == ^user.id and w.kid == ^kid,
      order_by: [asc: w.inserted_at]
    )
    |> Repo.all()
  end

  def enable_key_with_wrapper(%User{} = user, attrs) when is_map(attrs) do
    if get_active_key(user) do
      {:error, :already_enabled}
    else
      with {:ok, kid} <- fetch_string_key(attrs, :kid),
           {:ok, public_key_jwk} <- fetch_map_key(attrs, :public_key_jwk),
           {:ok, wrapper_attrs} <- fetch_map_key(attrs, :wrapper),
           {:ok, wrapper_type} <- fetch_string_key(wrapper_attrs, :type),
           {:ok, wrapped_private_key} <- fetch_binary_key(wrapper_attrs, :wrapped_private_key),
           {:ok, params} <- fetch_map_key(wrapper_attrs, :params),
           {:ok, fingerprint} <- fingerprint_public_key_jwk(public_key_jwk) do
        Repo.transaction(fn ->
          with {:ok, key} <-
                 %Key{}
                 |> Key.changeset(%{
                   user_id: user.id,
                   kid: kid,
                   public_key_jwk: public_key_jwk,
                   fingerprint: fingerprint,
                   active: true
                 })
                 |> Repo.insert(),
               {:ok, wrapper} <-
                 %KeyWrapper{}
                 |> KeyWrapper.changeset(%{
                   user_id: user.id,
                   kid: kid,
                   type: wrapper_type,
                   wrapped_private_key: wrapped_private_key,
                   params: params
                 })
                 |> Repo.insert() do
            %{key: key, wrapper: wrapper}
          else
            {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback(changeset)
          end
        end)
        |> case do
          {:ok, %{key: %Key{} = key, wrapper: %KeyWrapper{} = wrapper}} ->
            {:ok, %{key: key, wrapper: wrapper}}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:error, changeset}
        end
      end
    end
  end

  def public_keys_for_actor(%User{} = user) do
    user
    |> list_active_keys()
    |> Enum.map(fn %Key{} = key ->
      %{
        "kid" => key.kid,
        "fingerprint" => key.fingerprint,
        "created_at" => DateTime.to_iso8601(key.inserted_at)
      }
      |> Map.merge(key.public_key_jwk)
      |> Map.take(["kid", "kty", "crv", "x", "y", "created_at", "fingerprint"])
    end)
  end

  def fingerprint_public_key_jwk(%{} = jwk) do
    with {:ok, kty} <- fetch_string_key(jwk, "kty"),
         {:ok, crv} <- fetch_string_key(jwk, "crv"),
         {:ok, x} <- fetch_string_key(jwk, "x"),
         {:ok, y} <- fetch_string_key(jwk, "y") do
      canonical =
        "{\"crv\":#{Jason.encode!(crv)},\"kty\":#{Jason.encode!(kty)},\"x\":#{Jason.encode!(x)},\"y\":#{Jason.encode!(y)}}"

      digest = :crypto.hash(:sha256, canonical)
      {:ok, "sha256:" <> Base.url_encode64(digest, padding: false)}
    end
  end

  def fingerprint_public_key_jwk(_), do: {:error, :invalid_jwk}

  defp fetch_string_key(%{} = map, key) when is_binary(key) do
    case Map.get(map, key) do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: {:error, :invalid_key}, else: {:ok, value}

      _ ->
        {:error, :invalid_key}
    end
  end

  defp fetch_string_key(%{} = map, key) when is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> fetch_string_key(%{Atom.to_string(key) => value}, Atom.to_string(key))
      :error -> fetch_string_key(map, Atom.to_string(key))
    end
  end

  defp fetch_string_key(_map, _key), do: {:error, :invalid_key}

  defp fetch_map_key(%{} = map, key) when is_binary(key) do
    case Map.get(map, key) do
      %{} = value -> {:ok, value}
      _ -> {:error, :invalid_key}
    end
  end

  defp fetch_map_key(%{} = map, key) when is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, %{} = value} -> {:ok, value}
      {:ok, _} -> {:error, :invalid_key}
      :error -> fetch_map_key(map, Atom.to_string(key))
    end
  end

  defp fetch_map_key(_map, _key), do: {:error, :invalid_key}

  defp fetch_binary_key(%{} = map, key) when is_binary(key) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" ->
        {:ok, value}

      _ ->
        {:error, :invalid_key}
    end
  end

  defp fetch_binary_key(%{} = map, key) when is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> fetch_binary_key(%{Atom.to_string(key) => value}, Atom.to_string(key))
      :error -> fetch_binary_key(map, Atom.to_string(key))
    end
  end

  defp fetch_binary_key(_map, _key), do: {:error, :invalid_key}
end
