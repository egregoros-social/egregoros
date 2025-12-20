defmodule PleromaReduxWeb.MastodonAPI.StreamingController do
  use PleromaReduxWeb, :controller

  alias PleromaRedux.Auth
  alias PleromaRedux.User
  alias PleromaReduxWeb.MastodonAPI.StreamingSocket

  @known_streams MapSet.new(["public", "public:local", "user"])

  def index(conn, params) do
    streams = normalize_streams(Map.get(params, "stream"))

    with :ok <- validate_streams(streams),
         {:ok, current_user} <- maybe_require_auth(conn, streams) do
      WebSockAdapter.upgrade(
        conn,
        StreamingSocket,
        %{streams: streams, current_user: current_user},
        timeout: 120_000
      )
    else
      {:error, :missing_stream} ->
        conn
        |> send_resp(400, "Missing stream")
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

  defp validate_streams([]), do: {:error, :missing_stream}

  defp validate_streams(streams) when is_list(streams) do
    if Enum.all?(streams, &MapSet.member?(@known_streams, &1)) do
      :ok
    else
      {:error, :unknown_stream}
    end
  end

  defp maybe_require_auth(conn, streams) when is_list(streams) do
    if "user" in streams do
      case Auth.current_user(conn) do
        {:ok, %User{} = user} -> {:ok, user}
        _ -> {:error, :unauthorized}
      end
    else
      {:ok, nil}
    end
  end
end
