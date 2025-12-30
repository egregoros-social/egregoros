defmodule Egregoros.CustomEmojis do
  @moduledoc false

  alias Egregoros.SafeURL

  @type emoji :: %{shortcode: String.t(), url: String.t()}

  def from_object(%{data: %{} = data}), do: from_activity_tags(Map.get(data, "tag", []))
  def from_object(_), do: []

  def from_activity_tags(tags) do
    tags
    |> List.wrap()
    |> Enum.filter(&is_map/1)
    |> Enum.filter(&(Map.get(&1, "type") == "Emoji"))
    |> Enum.map(&parse_emoji_tag/1)
    |> Enum.filter(&safe_emoji?/1)
  end

  defp parse_emoji_tag(%{"name" => name, "icon" => icon})
       when is_binary(name) and is_map(icon) do
    shortcode =
      name
      |> String.trim()
      |> String.trim(":")

    url = icon_url(icon)

    if is_binary(url) and url != "" and shortcode != "" do
      %{shortcode: shortcode, url: url}
    end
  end

  defp parse_emoji_tag(_), do: nil

  defp icon_url(%{"url" => url}) when is_binary(url), do: url
  defp icon_url(%{"url" => [%{"href" => href} | _]}) when is_binary(href), do: href
  defp icon_url(%{"url" => [%{"url" => url} | _]}) when is_binary(url), do: url
  defp icon_url(_), do: nil

  defp safe_emoji?(%{shortcode: shortcode, url: url})
       when is_binary(shortcode) and is_binary(url) do
    shortcode = String.trim(shortcode)
    url = String.trim(url)

    shortcode != "" and url != "" and SafeURL.validate_http_url_no_dns(url) == :ok
  end

  defp safe_emoji?(_emoji), do: false
end
