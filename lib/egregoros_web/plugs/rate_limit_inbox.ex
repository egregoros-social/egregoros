defmodule EgregorosWeb.Plugs.RateLimitInbox do
  import Plug.Conn

  alias Egregoros.Domain
  alias Egregoros.RateLimiter

  @default_limit 120
  @default_interval_ms 10_000

  def init(opts), do: opts

  def call(conn, _opts) do
    {limit, interval_ms} = limits()
    key = rate_key(conn)

    case RateLimiter.allow?(:inbox, key, limit, interval_ms) do
      :ok ->
        conn

      {:error, :rate_limited} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(div(interval_ms, 1_000)))
        |> send_resp(429, "Too Many Requests")
        |> halt()
    end
  end

  defp limits do
    opts = Application.get_env(:egregoros, :rate_limit_inbox, [])

    limit =
      case Keyword.get(opts, :limit, @default_limit) do
        value when is_integer(value) and value >= 1 -> value
        _ -> @default_limit
      end

    interval_ms =
      case Keyword.get(opts, :interval_ms, @default_interval_ms) do
        value when is_integer(value) and value >= 1 -> value
        _ -> @default_interval_ms
      end

    {limit, interval_ms}
  end

  defp rate_key(conn) do
    source =
      conn
      |> signature_actor_domain()
      |> case do
        domain when is_binary(domain) and domain != "" -> domain
        _ -> ip_key(conn)
      end

    source <> "|" <> conn.request_path
  end

  defp signature_actor_domain(conn) do
    with key_id when is_binary(key_id) <- signature_key_id(conn),
         signer_ap_id when is_binary(signer_ap_id) <- signer_ap_id_from_key_id(key_id),
         %URI{} = uri <- URI.parse(signer_ap_id),
         domain when is_binary(domain) and domain != "" <- Domain.from_uri(uri) do
      domain
    else
      _ -> nil
    end
  end

  defp signature_key_id(conn) do
    conn
    |> get_req_header("signature")
    |> List.first()
    |> case do
      value when is_binary(value) ->
        extract_key_id_from_signature_header(value)

      _ ->
        conn
        |> get_req_header("authorization")
        |> List.first()
        |> extract_key_id_from_signature_header()
    end
  end

  defp extract_key_id_from_signature_header("Signature " <> rest) do
    extract_key_id_from_signature_header(rest)
  end

  defp extract_key_id_from_signature_header(rest) when is_binary(rest) do
    rest
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.find_value(fn part ->
      case String.split(part, "=", parts: 2) do
        [key, value] ->
          if String.downcase(String.trim(key)) == "keyid" do
            value |> String.trim() |> String.trim("\"")
          else
            nil
          end

        _ ->
          nil
      end
    end)
  end

  defp extract_key_id_from_signature_header(_), do: nil

  defp signer_ap_id_from_key_id(key_id) when is_binary(key_id) do
    key_id
    |> String.split("#", parts: 2)
    |> List.first()
    |> case do
      ap_id when is_binary(ap_id) and ap_id != "" -> ap_id
      _ -> nil
    end
  end

  defp signer_ap_id_from_key_id(_), do: nil

  defp ip_key(%Plug.Conn{remote_ip: remote_ip}) do
    remote_ip
    |> Tuple.to_list()
    |> Enum.join(".")
  end
end
