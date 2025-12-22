defmodule PleromaRedux.Federation.Actor do
  alias PleromaRedux.HTTP
  alias PleromaRedux.Federation.SignedFetch
  alias PleromaRedux.SafeURL
  alias PleromaRedux.Users

  def fetch_and_store(actor_url) when is_binary(actor_url) do
    with :ok <- SafeURL.validate_http_url(actor_url),
         {:ok, actor} <- fetch_actor(actor_url),
         {:ok, attrs} <- to_user_attrs(actor, actor_url),
         {:ok, user} <- Users.upsert_user(attrs) do
      {:ok, user}
    else
      {:error, _} = error -> error
      _ -> {:error, :actor_fetch_failed}
    end
  end

  defp fetch_actor(actor_url) when is_binary(actor_url) do
    case HTTP.get(actor_url, headers()) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        with {:ok, actor} <- decode_json(body) do
          actor =
            if sparse_actor?(actor) do
              case fetch_actor_signed(actor_url) do
                {:ok, signed_actor} -> signed_actor
                _ -> actor
              end
            else
              actor
            end

          {:ok, actor}
        end

      {:ok, %{status: status}} when status in [401, 403] ->
        fetch_actor_signed(actor_url)

      {:ok, _response} ->
        {:error, :actor_fetch_failed}

      {:error, _} = error ->
        error
    end
  end

  defp fetch_actor_signed(actor_url) when is_binary(actor_url) do
    with {:ok, %{status: status, body: body}} when status in 200..299 <-
           SignedFetch.get(actor_url, accept: "application/activity+json, application/ld+json"),
         {:ok, actor} <- decode_json(body) do
      {:ok, actor}
    else
      {:error, _} = error -> error
      _ -> {:error, :actor_fetch_failed}
    end
  end

  defp sparse_actor?(actor) when is_map(actor) do
    allowed_keys = MapSet.new(["@context", "id", "publicKey"])

    actor
    |> Map.keys()
    |> Enum.all?(&MapSet.member?(allowed_keys, &1))
  end

  defp sparse_actor?(_), do: false

  defp headers do
    [
      {"accept", "application/activity+json, application/ld+json"},
      {"user-agent", "pleroma-redux"}
    ]
  end

  defp decode_json(body) when is_map(body), do: {:ok, body}

  defp decode_json(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      _ -> {:error, :invalid_json}
    end
  end

  defp decode_json(_), do: {:error, :invalid_json}

  defp to_user_attrs(%{"id" => id} = actor, actor_url) when is_binary(id) and is_binary(actor_url) do
    if id != actor_url do
      {:error, :actor_id_mismatch}
    else
      inbox =
        actor
        |> Map.get("inbox")
        |> case do
          inbox when is_binary(inbox) and inbox != "" -> inbox
          _ -> default_endpoint(id, "inbox")
        end

      to_user_attrs(actor, id, inbox)
    end
  end

  defp to_user_attrs(%{"id" => id} = actor, _actor_url) when is_binary(id) do
    inbox =
      actor
      |> Map.get("inbox")
      |> case do
        inbox when is_binary(inbox) and inbox != "" -> inbox
        _ -> default_endpoint(id, "inbox")
      end

    to_user_attrs(actor, id, inbox)
  end

  defp to_user_attrs(_actor, _actor_url), do: {:error, :invalid_actor}

  defp to_user_attrs(%{} = actor, id, inbox) when is_binary(id) and is_binary(inbox) do
    public_key = get_in(actor, ["publicKey", "publicKeyPem"])

    if not is_binary(public_key) or public_key == "" do
      {:error, :missing_public_key}
    else
      domain =
        case URI.parse(id) do
          %URI{host: host} when is_binary(host) and host != "" -> host
          _ -> nil
        end

      nickname =
        actor
        |> Map.get("preferredUsername")
        |> case do
          value when is_binary(value) and value != "" -> value
          _ -> id |> URI.parse() |> Map.get(:path) |> fallback_nickname()
        end

      outbox =
        actor
        |> Map.get("outbox")
        |> case do
          value when is_binary(value) and value != "" -> value
          _ -> default_endpoint(id, "outbox")
        end

      with :ok <- SafeURL.validate_http_url(inbox),
           :ok <- SafeURL.validate_http_url(outbox) do
        attrs = %{
          nickname: nickname,
          domain: domain,
          ap_id: id,
          inbox: inbox,
          outbox: outbox,
          public_key: public_key,
          private_key: nil,
          local: false
        }

        attrs =
          attrs
          |> maybe_put_string(:name, Map.get(actor, "name"))
          |> maybe_put_string(:bio, Map.get(actor, "summary"))
          |> maybe_put_icon(actor, id)

        {:ok, attrs}
      end
    end
  end

  defp fallback_nickname(nil), do: "unknown"

  defp fallback_nickname(path) when is_binary(path) do
    path
    |> String.split("/", trim: true)
    |> List.last()
    |> case do
      nil -> "unknown"
      value -> value
    end
  end

  defp maybe_put_string(attrs, key, value)
       when is_map(attrs) and is_atom(key) and is_binary(value) do
    value = String.trim(value)
    if value == "", do: attrs, else: Map.put(attrs, key, value)
  end

  defp maybe_put_string(attrs, _key, _value), do: attrs

  defp maybe_put_icon(attrs, actor, actor_id) when is_map(attrs) and is_map(actor) do
    case icon_url(actor, actor_id) do
      url when is_binary(url) and url != "" -> Map.put(attrs, :avatar_url, url)
      _ -> attrs
    end
  end

  defp maybe_put_icon(attrs, _actor, _actor_id), do: attrs

  defp icon_url(%{} = actor, actor_id) when is_binary(actor_id) do
    actor
    |> Map.get("icon")
    |> extract_url()
    |> resolve_url(actor_id)
    |> case do
      url when is_binary(url) ->
        case SafeURL.validate_http_url(url) do
          :ok -> url
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp icon_url(_actor, _actor_id), do: nil

  defp extract_url(url) when is_binary(url), do: url
  defp extract_url(%{"href" => href}) when is_binary(href), do: href
  defp extract_url(%{"url" => url}), do: extract_url(url)

  defp extract_url(list) when is_list(list) do
    Enum.find_value(list, &extract_url/1)
  end

  defp extract_url(_), do: nil

  defp resolve_url(nil, _base), do: nil

  defp resolve_url(url, base) when is_binary(url) and is_binary(base) do
    url = String.trim(url)

    cond do
      url == "" ->
        nil

      String.starts_with?(url, ["http://", "https://"]) ->
        url

      true ->
        case URI.parse(base) do
          %URI{scheme: scheme, host: host}
          when scheme in ["http", "https"] and is_binary(host) and host != "" ->
            base
            |> URI.merge(url)
            |> URI.to_string()

          _ ->
            nil
        end
    end
  end

  defp resolve_url(_url, _base), do: nil

  defp default_endpoint(actor_id, suffix) when is_binary(actor_id) and is_binary(suffix) do
    String.trim_trailing(actor_id, "/") <> "/" <> suffix
  end

  defp default_endpoint(_actor_id, _suffix), do: nil
end
