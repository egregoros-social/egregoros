defmodule EgregorosWeb.MastodonAPI.Fallback do
  @moduledoc false

  def fallback_username(actor_ap_id) when is_binary(actor_ap_id) do
    case URI.parse(actor_ap_id) do
      %URI{path: path} when is_binary(path) and path != "" ->
        path
        |> String.split("/", trim: true)
        |> List.last()
        |> case do
          nil -> "unknown"
          value -> value
        end

      _ ->
        "unknown"
    end
  end

  def fallback_username(_actor_ap_id), do: "unknown"
end
