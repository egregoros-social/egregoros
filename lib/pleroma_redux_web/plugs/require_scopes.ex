defmodule PleromaReduxWeb.Plugs.RequireScopes do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, required_scopes) when is_list(required_scopes) do
    case PleromaRedux.AuthZ.authorize(conn, required_scopes) do
      :ok ->
        conn

      {:error, :unauthorized} ->
        conn
        |> send_resp(401, "Unauthorized")
        |> halt()

      {:error, :insufficient_scope} ->
        conn
        |> send_resp(403, "Forbidden")
        |> halt()

      {:error, _} ->
        conn
        |> send_resp(403, "Forbidden")
        |> halt()
    end
  end

  def call(conn, _opts) do
    conn
    |> send_resp(500, "Invalid scope configuration")
    |> halt()
  end
end

