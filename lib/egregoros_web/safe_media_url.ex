defmodule EgregorosWeb.SafeMediaURL do
  @moduledoc false

  alias Egregoros.SafeURL
  alias EgregorosWeb.Endpoint
  alias EgregorosWeb.URL

  @http_schemes ~w(http https)

  def safe(url) when is_binary(url) do
    url = String.trim(url)

    cond do
      url == "" ->
        nil

      String.starts_with?(url, "//") ->
        nil

      true ->
        case URI.parse(url) do
          %URI{scheme: nil, host: host} when is_binary(host) and host != "" ->
            nil

          %URI{scheme: scheme} when scheme in @http_schemes ->
            if same_origin?(url) do
              url
            else
              if SafeURL.validate_http_url_no_dns(url) == :ok, do: url, else: nil
            end

          %URI{scheme: nil} ->
            url = URL.absolute(url)
            if is_binary(url) and url != "", do: url, else: nil

          _ ->
            nil
        end
    end
  end

  def safe(_url), do: nil

  defp same_origin?(url) when is_binary(url) do
    with %URI{scheme: scheme, host: host, port: port}
         when scheme in @http_schemes and is_binary(host) and host != "" <- URI.parse(url),
         %URI{scheme: base_scheme, host: base_host, port: base_port}
         when base_scheme in @http_schemes and is_binary(base_host) and base_host != "" <-
           URI.parse(Endpoint.url()),
         true <- scheme == base_scheme,
         true <- String.downcase(host) == String.downcase(base_host),
         true <- normalize_port(port, scheme) == normalize_port(base_port, base_scheme) do
      true
    else
      _ -> false
    end
  end

  defp same_origin?(_url), do: false

  defp normalize_port(nil, "http"), do: 80
  defp normalize_port(nil, "https"), do: 443
  defp normalize_port(port, _scheme) when is_integer(port), do: port
  defp normalize_port(_port, "http"), do: 80
  defp normalize_port(_port, "https"), do: 443
  defp normalize_port(_port, _scheme), do: nil
end
