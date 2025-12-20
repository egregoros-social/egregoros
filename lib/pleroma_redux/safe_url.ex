defmodule PleromaRedux.SafeURL do
  @moduledoc false

  import Bitwise

  @http_schemes ~w(http https)

  def validate_http_url(url) when is_binary(url) do
    uri = URI.parse(url)

    with scheme when scheme in @http_schemes <- uri.scheme,
         host when is_binary(host) and host != "" <- uri.host,
         :ok <- validate_host(host) do
      :ok
    else
      _ -> {:error, :unsafe_url}
    end
  end

  def validate_http_url(_), do: {:error, :unsafe_url}

  defp validate_host("localhost"), do: {:error, :unsafe_url}

  defp validate_host(host) when is_binary(host) do
    if ip_literal?(host) do
      case :inet.parse_address(String.to_charlist(host)) do
        {:ok, ip} ->
          if private_ip?(ip), do: {:error, :unsafe_url}, else: :ok

        {:error, _} ->
          {:error, :unsafe_url}
      end
    else
      case PleromaRedux.DNS.lookup_ips(host) do
        {:ok, ips} when is_list(ips) and ips != [] ->
          if Enum.any?(ips, &private_ip?/1), do: {:error, :unsafe_url}, else: :ok

        _ ->
          {:error, :unsafe_url}
      end
    end
  end

  defp validate_host(_), do: {:error, :unsafe_url}

  defp ip_literal?(host) when is_binary(host) do
    String.contains?(host, ":") or
      String.match?(host, ~r/^\d{1,3}(\.\d{1,3}){3}$/)
  end

  defp private_ip?({10, _, _, _}), do: true
  defp private_ip?({127, _, _, _}), do: true
  defp private_ip?({0, _, _, _}), do: true
  defp private_ip?({169, 254, _, _}), do: true
  defp private_ip?({172, second, _, _}) when second in 16..31, do: true
  defp private_ip?({192, 168, _, _}), do: true
  defp private_ip?({100, second, _, _}) when second in 64..127, do: true
  defp private_ip?({_, _, _, _}), do: false

  defp private_ip?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp private_ip?({first, _, _, _, _, _, _, _}) when (first &&& 0xFE00) == 0xFC00, do: true
  defp private_ip?({first, _, _, _, _, _, _, _}) when (first &&& 0xFFC0) == 0xFE80, do: true
  defp private_ip?({_, _, _, _, _, _, _, _}), do: false
end
