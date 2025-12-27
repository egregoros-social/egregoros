defmodule Egregoros.Federation.SignedFetch do
  alias Egregoros.Domain
  alias Egregoros.Federation.InternalFetchActor
  alias Egregoros.HTTP
  alias Egregoros.RateLimiter
  alias Egregoros.SafeURL
  alias Egregoros.Signature.HTTP, as: HTTPSignature

  @default_accept "application/activity+json, application/ld+json"
  @default_user_agent "egregoros"
  @signed_headers ["(request-target)", "host", "date"]

  def get(url, opts \\ []) when is_binary(url) and is_list(opts) do
    accept = Keyword.get(opts, :accept, @default_accept)
    user_agent = Keyword.get(opts, :user_agent, @default_user_agent)

    with :ok <- SafeURL.validate_http_url(url),
         :ok <- rate_limit(url),
         {:ok, actor} <- InternalFetchActor.get_actor(),
         {:ok, signed} <- HTTPSignature.sign_request(actor, "get", url, "", @signed_headers),
         {:ok, response} <- HTTP.get(url, headers(signed, accept, user_agent)) do
      {:ok, response}
    else
      {:error, :rate_limited} = error -> error
      {:error, _} = error -> error
      _ -> {:error, :signed_fetch_failed}
    end
  end

  defp headers(signed, accept, user_agent)
       when is_map(signed) and is_binary(accept) and is_binary(user_agent) do
    [
      {"accept", accept},
      {"user-agent", user_agent},
      {"host", signed.host},
      {"date", signed.date},
      {"signature", signed.signature},
      {"authorization", signed.authorization}
    ]
  end

  defp rate_limit(url) when is_binary(url) do
    opts = Application.get_env(:egregoros, :rate_limit_signed_fetch, [])
    limit = opts |> Keyword.get(:limit, 200) |> normalize_limit(200)
    interval_ms = opts |> Keyword.get(:interval_ms, 10_000) |> normalize_interval_ms(10_000)
    key = url |> URI.parse() |> Domain.from_uri()

    case key do
      value when is_binary(value) and value != "" ->
        RateLimiter.allow?(:signed_fetch, value, limit, interval_ms)

      _ ->
        :ok
    end
  end

  defp normalize_limit(value, default) when is_integer(default) and default >= 1 do
    case value do
      v when is_integer(v) and v >= 1 -> v
      _ -> default
    end
  end

  defp normalize_interval_ms(value, default) when is_integer(default) and default >= 1 do
    case value do
      v when is_integer(v) and v >= 1 -> v
      _ -> default
    end
  end
end
