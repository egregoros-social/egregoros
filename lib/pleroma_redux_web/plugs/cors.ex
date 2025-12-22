defmodule PleromaReduxWeb.Plugs.CORS do
  @moduledoc false

  import Plug.Conn

  @default_paths ["/api", "/oauth"]
  @default_methods ~w(GET POST PUT PATCH DELETE OPTIONS)
  @default_expose_headers ["link"]
  @default_allow_headers "authorization,content-type,accept"
  @default_max_age 86_400

  def init(opts) do
    config = Application.get_env(:pleroma_redux, __MODULE__, [])

    opts
    |> Keyword.merge(config)
    |> Keyword.put_new(:paths, @default_paths)
    |> Keyword.put_new(:origins, ["*"])
    |> Keyword.put_new(:methods, @default_methods)
    |> Keyword.put_new(:expose_headers, @default_expose_headers)
    |> Keyword.put_new(:max_age, @default_max_age)
    |> Keyword.put_new(:allow_credentials, false)
  end

  def call(conn, opts) do
    if cors_path?(conn.request_path, Keyword.fetch!(opts, :paths)) do
      origin = conn |> get_req_header("origin") |> List.first()

      if is_binary(origin) and origin != "" do
        conn
        |> maybe_put_origin(origin, opts)
        |> maybe_put_credentials(opts)
        |> put_resp_header(
          "access-control-expose-headers",
          opts |> Keyword.fetch!(:expose_headers) |> Enum.join(",")
        )
        |> maybe_handle_preflight(opts)
      else
        conn
      end
    else
      conn
    end
  end

  defp cors_path?(request_path, paths) when is_binary(request_path) and is_list(paths) do
    Enum.any?(paths, &String.starts_with?(request_path, &1))
  end

  defp cors_path?(_request_path, _paths), do: false

  defp maybe_put_origin(conn, origin, opts) do
    case allowed_origin(origin, Keyword.fetch!(opts, :origins), Keyword.fetch!(opts, :allow_credentials)) do
      nil ->
        conn

      allow_origin ->
        conn
        |> put_resp_header("access-control-allow-origin", allow_origin)
        |> maybe_put_vary_origin(allow_origin)
    end
  end

  defp allowed_origin(_origin, ["*"], false), do: "*"
  defp allowed_origin(origin, ["*"], true), do: origin

  defp allowed_origin(origin, origins, _allow_credentials)
       when is_binary(origin) and is_list(origins) do
    if origin in origins, do: origin, else: nil
  end

  defp allowed_origin(_origin, _origins, _allow_credentials), do: nil

  defp maybe_put_vary_origin(conn, "*"), do: conn

  defp maybe_put_vary_origin(conn, _origin) do
    existing = conn |> get_resp_header("vary") |> List.first()

    cond do
      not is_binary(existing) or existing == "" ->
        put_resp_header(conn, "vary", "origin")

      String.contains?(String.downcase(existing), "origin") ->
        conn

      true ->
        put_resp_header(conn, "vary", existing <> ", origin")
    end
  end

  defp maybe_put_credentials(conn, opts) do
    if Keyword.fetch!(opts, :allow_credentials) do
      put_resp_header(conn, "access-control-allow-credentials", "true")
    else
      conn
    end
  end

  defp maybe_handle_preflight(conn, opts) do
    if conn.method == "OPTIONS" do
      methods = opts |> Keyword.fetch!(:methods) |> Enum.join(",")

      conn
      |> put_resp_header("access-control-allow-methods", methods)
      |> put_resp_header("access-control-allow-headers", allow_headers(conn))
      |> put_resp_header("access-control-max-age", Integer.to_string(Keyword.fetch!(opts, :max_age)))
      |> send_resp(204, "")
      |> halt()
    else
      conn
    end
  end

  defp allow_headers(conn) do
    case get_req_header(conn, "access-control-request-headers") do
      [headers | _] when is_binary(headers) and headers != "" ->
        headers

      _ ->
        @default_allow_headers
    end
  end
end

