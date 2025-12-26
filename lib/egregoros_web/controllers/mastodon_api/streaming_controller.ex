defmodule EgregorosWeb.MastodonAPI.StreamingController do
  use EgregorosWeb, :controller

  import Plug.Conn, only: [get_req_header: 2, put_resp_header: 3, send_resp: 3, halt: 1]

  alias Egregoros.OAuth
  alias Egregoros.OAuth.Token
  alias Egregoros.User
  alias EgregorosWeb.MastodonAPI.StreamingStreams
  alias EgregorosWeb.MastodonAPI.StreamingSocket

  def index(conn, %{"stream" => stream, "scope" => scope} = params)
      when is_binary(stream) and is_binary(scope) do
    params =
      params
      |> Map.delete("scope")
      |> Map.put("stream", stream <> ":" <> scope)

    index(conn, params)
  end

  def index(conn, params) do
    with :ok <- validate_websocket_upgrade(conn),
         streams <- normalize_streams(Map.get(params, "stream")),
         :ok <- validate_streams(streams),
         {conn, access_token} <- maybe_echo_protocol_and_get_access_token(conn, params),
         {:ok, current_user, oauth_token} <- authenticate_access_token(access_token),
         :ok <- authorize_user_streams(streams, current_user) do
      WebSockAdapter.upgrade(
        conn,
        StreamingSocket,
        %{
          streams: streams,
          current_user: current_user,
          oauth_token: oauth_token
        },
        timeout: 120_000
      )
    else
      {:error, :websocket_upgrade_required} ->
        conn
        |> send_resp(400, "WebSocket upgrade required")
        |> halt()

      {:error, :unknown_stream} ->
        conn
        |> send_resp(400, "Unknown stream")
        |> halt()

      {:error, :unauthorized} ->
        conn
        |> send_resp(401, "Unauthorized")
        |> halt()
    end
  end

  defp normalize_streams(nil), do: []

  defp normalize_streams(stream) when is_binary(stream) do
    stream
    |> String.trim()
    |> case do
      "" -> []
      value -> [value]
    end
  end

  defp normalize_streams(streams) when is_list(streams) do
    streams
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_streams(_), do: []

  defp validate_streams(streams) when is_list(streams) do
    if Enum.all?(streams, &(&1 in StreamingStreams.known_streams())) do
      :ok
    else
      {:error, :unknown_stream}
    end
  end

  defp validate_websocket_upgrade(conn) do
    case WebSockAdapter.UpgradeValidation.validate_upgrade(conn) do
      :ok -> :ok
      {:error, _reason} -> {:error, :websocket_upgrade_required}
    end
  end

  defp maybe_echo_protocol_and_get_access_token(conn, params) do
    requested_protocol = select_subprotocol(conn)

    conn =
      if is_binary(requested_protocol) do
        put_resp_header(conn, "sec-websocket-protocol", requested_protocol)
      else
        conn
      end

    access_token =
      case Map.get(params, "access_token") do
        token when is_binary(token) and token != "" -> String.trim(token)
        _ -> requested_protocol
      end

    {conn, access_token}
  end

  defp select_subprotocol(conn) do
    conn
    |> get_req_header("sec-websocket-protocol")
    |> Enum.flat_map(&Plug.Conn.Utils.list/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> List.first()
  end

  defp authenticate_access_token(nil), do: {:ok, nil, nil}

  defp authenticate_access_token(token) when is_binary(token) do
    case OAuth.get_token(token) do
      %Token{user: %User{} = user} = oauth_token ->
        {:ok, user, oauth_token}

      _ ->
        {:error, :unauthorized}
    end
  end

  defp authorize_user_streams(streams, current_user) when is_list(streams) do
    if Enum.any?(streams, &(&1 in StreamingStreams.user_streams())) and current_user == nil do
      {:error, :unauthorized}
    else
      :ok
    end
  end
end
