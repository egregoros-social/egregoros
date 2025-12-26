defmodule Egregoros.Federation.WebFinger do
  alias Egregoros.HTTP
  alias Egregoros.SafeURL

  def lookup(handle) when is_binary(handle) do
    with {:ok, username, domain} <- parse_handle(handle),
         url <-
           "https://" <>
             domain <> "/.well-known/webfinger?resource=acct:" <> username <> "@" <> domain,
         :ok <- SafeURL.validate_http_url(url),
         {:ok, %{status: status, body: body}} when status in 200..299 <- HTTP.get(url, headers()),
         {:ok, jrd} <- decode_json(body),
         {:ok, actor_url} <- find_actor_url(jrd) do
      {:ok, actor_url}
    else
      {:error, _} = error -> error
      _ -> {:error, :webfinger_failed}
    end
  end

  defp headers do
    [
      {"accept", "application/jrd+json, application/json"},
      {"user-agent", "egregoros"}
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

  defp find_actor_url(%{"links" => links}) when is_list(links) do
    links
    |> Enum.find(fn link ->
      Map.get(link, "rel") == "self" and is_binary(Map.get(link, "href"))
    end)
    |> case do
      %{"href" => href} -> {:ok, href}
      _ -> {:error, :not_found}
    end
  end

  defp find_actor_url(_), do: {:error, :not_found}

  defp parse_handle(handle) do
    handle =
      handle
      |> String.trim()
      |> String.trim_leading("@")

    case String.split(handle, "@", parts: 2) do
      [username, domain] when username != "" and domain != "" ->
        {:ok, username, domain}

      _ ->
        {:error, :invalid_handle}
    end
  end
end
