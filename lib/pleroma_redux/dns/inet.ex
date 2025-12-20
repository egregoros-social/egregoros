defmodule PleromaRedux.DNS.Inet do
  @behaviour PleromaRedux.DNS

  @impl true
  def lookup_ips(host) when is_binary(host) do
    host = String.to_charlist(host)

    ips =
      [:inet, :inet6]
      |> Enum.flat_map(fn family ->
        case :inet.getaddrs(host, family) do
          {:ok, addrs} -> addrs
          {:error, _} -> []
        end
      end)

    case ips do
      [] -> {:error, :nxdomain}
      _ -> {:ok, ips}
    end
  end
end

