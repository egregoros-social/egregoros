defmodule PleromaReduxWeb.BodyReader do
  @moduledoc false

  alias Plug.Conn

  def read_body(conn, opts) do
    case Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        existing = Map.get(conn.assigns, :raw_body, "")
        {:ok, body, Conn.assign(conn, :raw_body, existing <> body)}

      {:more, body, conn} ->
        existing = Map.get(conn.assigns, :raw_body, "")
        {:more, body, Conn.assign(conn, :raw_body, existing <> body)}

      {:error, _reason} = error ->
        error
    end
  end
end
