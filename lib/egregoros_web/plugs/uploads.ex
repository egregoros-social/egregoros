defmodule EgregorosWeb.Plugs.Uploads do
  @behaviour Plug

  import Plug.Conn

  alias Egregoros.Media
  alias Egregoros.Users

  def init(_opts) do
    uploads_root = uploads_root()

    static_opts =
      Plug.Static.init(
        at: "/uploads",
        from: uploads_root,
        gzip: false,
        only_matching: ~w(avatars banners media)
      )

    %{static_opts: static_opts}
  end

  def call(%Plug.Conn{request_path: "/uploads" <> _rest} = conn, %{static_opts: static_opts}) do
    conn = fetch_session(conn)

    case conn.request_path do
      "/uploads/media/" <> _ ->
        user = current_user(conn)

        if Media.local_href_visible_to?(conn.request_path, user) do
          serve_static(conn, static_opts)
        else
          not_found(conn)
        end

      "/uploads/avatars/" <> _ ->
        serve_static(conn, static_opts)

      "/uploads/banners/" <> _ ->
        serve_static(conn, static_opts)

      _ ->
        not_found(conn)
    end
  end

  def call(conn, _opts), do: conn

  defp current_user(conn) do
    case get_session(conn, :user_id) do
      id when is_integer(id) ->
        Users.get(id)

      id when is_binary(id) ->
        case Integer.parse(id) do
          {int, ""} -> Users.get(int)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp serve_static(conn, static_opts) do
    conn = Plug.Static.call(conn, static_opts)
    if conn.halted, do: conn, else: not_found(conn)
  end

  defp not_found(conn) do
    conn
    |> send_resp(404, "Not Found")
    |> halt()
  end

  defp uploads_root do
    priv_dir =
      :egregoros
      |> :code.priv_dir()
      |> to_string()

    default = Path.join([priv_dir, "static", "uploads"])

    Application.get_env(:egregoros, :uploads_dir, default)
  end
end
