defmodule PleromaRedux.CustomEmojis do
  @moduledoc false

  @type emoji :: %{shortcode: String.t(), url: String.t()}

  def from_object(%{data: %{} = data}), do: from_activity_tags(Map.get(data, "tag", []))
  def from_object(_), do: []

  def from_activity_tags(tags) do
    tags
    |> List.wrap()
    |> Enum.filter(&is_map/1)
    |> Enum.filter(&(Map.get(&1, "type") == "Emoji"))
    |> Enum.map(&parse_emoji_tag/1)
    |> Enum.filter(&is_map/1)
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
end

