defmodule PleromaReduxWeb.Plugs.FetchOptionalAuth do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    cond do
      conn.assigns[:current_user] != nil ->
        conn

      authorization_header?(conn) ->
        case PleromaRedux.Auth.current_user(conn) do
          {:ok, user} ->
            assign(conn, :current_user, user)

          {:error, _reason} ->
            conn
            |> send_resp(401, "Unauthorized")
            |> halt()
        end

      true ->
        conn
    end
  end

  defp authorization_header?(conn) do
    case get_req_header(conn, "authorization") do
      [value | _] when is_binary(value) -> String.trim(value) != ""
      _ -> false
    end
  end
end
