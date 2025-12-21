defmodule PleromaReduxWeb.URL do
  alias PleromaReduxWeb.Endpoint

  def absolute(nil), do: nil
  def absolute(""), do: ""

  def absolute(url) when is_binary(url) do
    absolute(url, Endpoint.url())
  end

  def absolute(nil, _base), do: nil
  def absolute("", _base), do: ""

  def absolute(url, base) when is_binary(url) do
    url = String.trim(url)

    cond do
      url == "" ->
        ""

      String.starts_with?(url, ["http://", "https://"]) ->
        url

      base_url?(base) ->
        path = if String.starts_with?(url, "/"), do: url, else: "/" <> url

        base
        |> URI.merge(path)
        |> URI.to_string()

      true ->
        absolute(url)
    end
  end

  def absolute(url, _base), do: absolute(url)

  defp base_url?(base) when is_binary(base) do
    case URI.parse(base) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        true

      _ ->
        false
    end
  end

  defp base_url?(_base), do: false

  def local_object_uuid(ap_id) when is_binary(ap_id) do
    base = Endpoint.url() <> "/objects/"

    if String.starts_with?(ap_id, base) do
      uuid = String.replace_prefix(ap_id, base, "")
      if uuid == "", do: nil, else: uuid
    else
      nil
    end
  end

  def local_object_uuid(_ap_id), do: nil
end
