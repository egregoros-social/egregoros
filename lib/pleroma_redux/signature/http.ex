defmodule PleromaRedux.Signature.HTTP do
  @behaviour PleromaRedux.Signature

  alias PleromaRedux.User
  alias PleromaRedux.Users

  @default_headers ["(request-target)", "host", "date", "digest", "content-length"]

  @impl true
  def verify_request(conn) do
    headers = normalize_headers(conn.req_headers)

    with {:ok, key_id, signature, headers_param} <- parse_signature(headers),
         signer_ap_id when is_binary(signer_ap_id) <- signer_ap_id_from_key_id(key_id),
         {:ok, key} <- public_key_for_key_id(key_id),
         :ok <- validate_date(headers, headers_param),
         {:ok, method} <- method_atom(conn.method) do
      headers_param = normalize_header_names(headers_param)
      headers = augment_headers(headers, conn, headers_param)

      request_targets(conn, method)
      |> Enum.any?(fn request_target ->
        signature_string = signature_string(request_target, headers, headers_param)
        verify_rsa(signature, signature_string, key)
      end)
      |> case do
        true -> {:ok, signer_ap_id}
        false -> {:error, :invalid_signature}
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_signature}
    end
  end

  def sign_request(%User{} = user, method, url, body, headers_param \\ @default_headers)
      when is_binary(method) and is_binary(url) and is_binary(body) do
    headers_param = normalize_header_names(headers_param)

    with {:ok, method} <- method_atom(method),
         {:ok, private_key} <- private_key_from_user(user) do
      uri = URI.parse(url)
      request_target = method <> " " <> request_path_with_query(uri)
      date = signed_date()
      host = host_header_for_uri(uri)
      content_length = Integer.to_string(byte_size(body))
      digest = digest_for(body)

      headers =
        %{
          "date" => date,
          "host" => host,
          "content-length" => content_length,
          "digest" => digest
        }

      signature_string = signature_string(request_target, headers, headers_param)
      signature = :public_key.sign(signature_string, :sha256, private_key) |> Base.encode64()

      signature_params =
        "keyId=\"#{user.ap_id}#main-key\"," <>
          "algorithm=\"rsa-sha256\"," <>
          "headers=\"#{Enum.join(headers_param, " ")}\"," <>
          "signature=\"#{signature}\""

      {:ok,
       %{
         signature: signature_params,
         authorization: "Signature " <> signature_params,
         date: date,
         digest: digest,
         content_length: content_length,
         host: host,
         headers: headers_param
       }}
    end
  end

  defp normalize_headers(headers) do
    Enum.into(headers, %{}, fn {key, value} -> {String.downcase(key), value} end)
  end

  defp parse_signature(headers) do
    cond do
      is_binary(Map.get(headers, "signature")) ->
        headers
        |> Map.get("signature")
        |> parse_signature_value()

      is_binary(Map.get(headers, "authorization")) ->
        headers
        |> Map.get("authorization")
        |> parse_signature_value()

      true ->
        {:error, :missing_signature}
    end
  end

  defp parse_signature_value("Signature " <> rest), do: parse_signature_params(rest)
  defp parse_signature_value(rest) when is_binary(rest), do: parse_signature_params(rest)
  defp parse_signature_value(_), do: {:error, :invalid_signature}

  defp parse_signature_params(rest) when is_binary(rest) do
    params =
      rest
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reduce(%{}, fn part, acc ->
        case String.split(part, "=", parts: 2) do
          [key, value] ->
            Map.put(acc, key, value |> String.trim("\""))

          _ ->
            acc
        end
      end)

    with key_id when is_binary(key_id) <- Map.get(params, "keyId"),
         signature_b64 when is_binary(signature_b64) <- Map.get(params, "signature") do
      headers_param =
        params
        |> Map.get("headers", "(request-target) date")
        |> String.split()
        |> Enum.map(&String.downcase/1)

      case Base.decode64(signature_b64) do
        {:ok, decoded} ->
          {:ok, key_id, decoded, headers_param}

        :error ->
          {:error, :invalid_signature}
      end
    else
      _ -> {:error, :invalid_signature}
    end
  end

  defp public_key_for_key_id(key_id) when is_binary(key_id) do
    ap_id = key_id |> String.split("#") |> List.first()

    case Users.get_by_ap_id(ap_id) do
      %{} = user ->
        case :public_key.pem_decode(user.public_key) do
          [entry] ->
            try do
              {:ok, :public_key.pem_entry_decode(entry)}
            rescue
              _ -> {:error, :unknown_key}
            end

          _ ->
            {:error, :unknown_key}
        end

      _ ->
        fetch_public_key_for_actor(ap_id)
    end
  end

  defp public_key_for_key_id(_), do: {:error, :invalid_signature}

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

  defp fetch_public_key_for_actor(ap_id) when is_binary(ap_id) do
    with {:ok, user} <- PleromaRedux.Federation.Actor.fetch_and_store(ap_id),
         [entry] <- :public_key.pem_decode(user.public_key) do
      {:ok, :public_key.pem_entry_decode(entry)}
    else
      {:error, _} = error -> error
      _ -> {:error, :unknown_key}
    end
  end

  defp signature_string(request_target, headers, headers_param) do
    headers_param
    |> Enum.map(fn
      "(request-target)" -> "(request-target): #{request_target}"
      "@request-target" -> "@request-target: #{request_target}"
      header -> "#{header}: #{Map.get(headers, header, "")}"
    end)
    |> Enum.join("\n")
  end

  defp verify_rsa(signature, data, public_key) do
    :public_key.verify(data, :sha256, signature, public_key)
  end

  defp request_targets(conn, method) do
    base = method <> " " <> conn.request_path

    case conn.query_string do
      "" -> [base]
      nil -> [base]
      qs -> [base, base <> "?" <> qs]
    end
  end

  defp method_atom(method) when is_binary(method) do
    case String.downcase(method) do
      "get" -> {:ok, "get"}
      "post" -> {:ok, "post"}
      "put" -> {:ok, "put"}
      "patch" -> {:ok, "patch"}
      "delete" -> {:ok, "delete"}
      "head" -> {:ok, "head"}
      "options" -> {:ok, "options"}
      _ -> {:error, :invalid_method}
    end
  end

  defp validate_date(headers, headers_param) do
    headers_param = normalize_header_names(headers_param)

    if "date" in headers_param do
      case Map.get(headers, "date") do
        nil -> {:error, :missing_date}
        date -> check_date_skew(date)
      end
    else
      {:error, :missing_date}
    end
  end

  defp check_date_skew(date_header) do
    with {:ok, signed_at} <- parse_http_date(date_header) do
      diff = DateTime.diff(DateTime.utc_now(), signed_at) |> abs()

      if diff <= max_skew_seconds() do
        :ok
      else
        {:error, :date_skew}
      end
    end
  end

  defp parse_http_date(date_header) when is_binary(date_header) do
    case :httpd_util.convert_request_date(String.to_charlist(date_header)) do
      {{year, month, day}, {hour, minute, second}} ->
        with {:ok, naive} <- NaiveDateTime.from_erl({{year, month, day}, {hour, minute, second}}),
             {:ok, dt} <- DateTime.from_naive(naive, "Etc/UTC") do
          {:ok, dt}
        end

      :bad_date ->
        {:error, :invalid_date}
    end
  end

  defp max_skew_seconds do
    Application.get_env(:pleroma_redux, :signature_skew_seconds, 300)
  end

  defp normalize_header_names(headers_param) do
    headers_param
    |> Enum.map(&String.downcase/1)
  end

  defp augment_headers(headers, conn, headers_param) do
    headers_param_set = MapSet.new(headers_param)

    headers
    |> maybe_put_host(conn, headers_param_set)
    |> maybe_put_content_length(conn, headers_param_set)
    |> maybe_put_digest(conn, headers_param_set)
  end

  defp maybe_put_host(headers, conn, headers_param_set) do
    if MapSet.member?(headers_param_set, "host") and not Map.has_key?(headers, "host") do
      Map.put(headers, "host", host_header_for_conn(conn))
    else
      headers
    end
  end

  defp maybe_put_content_length(headers, conn, headers_param_set) do
    if MapSet.member?(headers_param_set, "content-length") and is_binary(raw_body(conn)) do
      Map.put(headers, "content-length", Integer.to_string(byte_size(raw_body(conn))))
    else
      headers
    end
  end

  defp maybe_put_digest(headers, conn, headers_param_set) do
    if MapSet.member?(headers_param_set, "digest") and is_binary(raw_body(conn)) do
      Map.put(headers, "digest", digest_for(raw_body(conn)))
    else
      headers
    end
  end

  defp raw_body(conn) do
    Map.get(conn.assigns, :raw_body)
  end

  defp digest_for(body) do
    "SHA-256=" <> (:crypto.hash(:sha256, body) |> Base.encode64())
  end

  defp host_header_for_conn(conn) do
    forwarded_host = conn |> Plug.Conn.get_req_header("x-forwarded-host") |> List.first()
    forwarded_port = conn |> Plug.Conn.get_req_header("x-forwarded-port") |> List.first()
    forwarded_proto = conn |> Plug.Conn.get_req_header("x-forwarded-proto") |> List.first()

    host =
      forwarded_host
      |> first_forwarded_value()
      |> case do
        nil -> conn.host
        value -> value
      end

    scheme =
      case forwarded_proto do
        "https" -> :https
        "http" -> :http
        _ -> conn.scheme
      end

    port =
      case parse_forwarded_port(forwarded_port) do
        {:ok, port} ->
          port

        :error ->
          if is_binary(forwarded_proto) do
            default_port_for_scheme(scheme)
          else
            conn.port
          end
      end

    if host_has_port?(host) or is_nil(port) or port == default_port_for_scheme(scheme) do
      host
    else
      "#{host}:#{port}"
    end
  end

  defp first_forwarded_value(nil), do: nil

  defp first_forwarded_value(value) when is_binary(value) do
    value
    |> String.split(",", parts: 2)
    |> List.first()
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp parse_forwarded_port(nil), do: :error

  defp parse_forwarded_port(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {port, ""} when port > 0 -> {:ok, port}
      _ -> :error
    end
  end

  defp default_port_for_scheme(:https), do: 443
  defp default_port_for_scheme(_), do: 80

  defp host_has_port?("[" <> rest) do
    String.contains?(rest, "]:")
  end

  defp host_has_port?(host) when is_binary(host) do
    String.contains?(host, ":")
  end

  defp host_header_for_uri(%URI{} = uri) do
    default_port = URI.default_port(uri.scheme)

    if uri.port in [nil, default_port] do
      uri.host
    else
      "#{uri.host}:#{uri.port}"
    end
  end

  defp request_path_with_query(%URI{} = uri) do
    path =
      case uri.path do
        nil -> "/"
        "" -> "/"
        value -> value
      end

    case uri.query do
      nil -> path
      "" -> path
      query -> path <> "?" <> query
    end
  end

  defp signed_date do
    :httpd_util.rfc1123_date()
    |> List.to_string()
  end

  defp private_key_from_user(%User{private_key: pem}) when is_binary(pem) do
    [entry] = :public_key.pem_decode(pem)
    {:ok, :public_key.pem_entry_decode(entry)}
  end
end
