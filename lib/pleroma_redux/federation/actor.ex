defmodule PleromaRedux.Federation.Actor do
  alias PleromaRedux.HTTP
  alias PleromaRedux.SafeURL
  alias PleromaRedux.Users

  def fetch_and_store(actor_url) when is_binary(actor_url) do
    with :ok <- SafeURL.validate_http_url(actor_url),
         {:ok, %{status: status, body: body}} when status in 200..299 <-
           HTTP.get(actor_url, headers()),
         {:ok, actor} <- decode_json(body),
         {:ok, attrs} <- to_user_attrs(actor, actor_url),
         {:ok, user} <- Users.upsert_user(attrs) do
      {:ok, user}
    else
      {:error, _} = error -> error
      _ -> {:error, :actor_fetch_failed}
    end
  end

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

  defp to_user_attrs(%{"id" => id, "inbox" => inbox} = actor, actor_url)
       when is_binary(id) and is_binary(inbox) and is_binary(actor_url) do
    if id != actor_url do
      {:error, :actor_id_mismatch}
    else
      to_user_attrs(actor, id, inbox)
    end
  end

  defp to_user_attrs(%{"id" => id, "inbox" => inbox} = actor, _actor_url)
       when is_binary(id) and is_binary(inbox) do
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
          value when is_binary(value) -> value
          _ -> id <> "/outbox"
        end

      with :ok <- SafeURL.validate_http_url(inbox),
           :ok <- SafeURL.validate_http_url(outbox) do
        {:ok,
         %{
           nickname: nickname,
           domain: domain,
           ap_id: id,
           inbox: inbox,
           outbox: outbox,
           public_key: public_key,
           private_key: nil,
           local: false,
           name: Map.get(actor, "name"),
           bio: Map.get(actor, "summary"),
           avatar_url: icon_url(actor)
         }}
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

  defp icon_url(%{"icon" => %{"url" => url}}) when is_binary(url), do: url
  defp icon_url(%{"icon" => url}) when is_binary(url), do: url
  defp icon_url(_), do: nil
end
