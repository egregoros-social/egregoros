defmodule Egregoros.EmojiReactions do
  @moduledoc false

  alias Egregoros.CustomEmojis
  alias Egregoros.Domain
  alias EgregorosWeb.Endpoint
  alias EgregorosWeb.SafeMediaURL

  def normalize_content(content) when is_binary(content) do
    content = String.trim(content)

    if String.starts_with?(content, ":") and String.ends_with?(content, ":") and
         String.length(content) > 2 do
      content
      |> String.trim_leading(":")
      |> String.trim_trailing(":")
    else
      content
    end
  end

  def normalize_content(_content), do: nil

  def find_custom_emoji_url(shortcode, tags) when is_binary(shortcode) do
    tags
    |> CustomEmojis.from_activity_tags()
    |> Enum.find_value(fn
      %{shortcode: ^shortcode, url: url} when is_binary(url) ->
        SafeMediaURL.safe(url)

      _ ->
        nil
    end)
  end

  def find_custom_emoji_url(_shortcode, _tags), do: nil

  def display_name(shortcode, nil) when is_binary(shortcode), do: shortcode

  def display_name(shortcode, url) when is_binary(shortcode) and is_binary(url) do
    url = SafeMediaURL.safe(url)

    with url when is_binary(url) <- url,
         %URI{} = uri <- URI.parse(url),
         host when is_binary(host) and host != "" <- Domain.from_uri(uri),
         false <- host in local_domains() do
      shortcode <> "@" <> host
    else
      _ -> shortcode
    end
  end

  def display_name(shortcode, _url) when is_binary(shortcode), do: shortcode

  def local_domains do
    case URI.parse(Endpoint.url()) do
      %URI{} = uri -> Domain.aliases_from_uri(uri)
      _ -> []
    end
  end
end
