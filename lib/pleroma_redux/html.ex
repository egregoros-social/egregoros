defmodule PleromaRedux.HTML do
  @moduledoc false

  @default_scrubber PleromaRedux.HTML.Scrubber.Default

  alias PleromaReduxWeb.Endpoint

  defguardp valid_codepoint(code)
            when is_integer(code) and code >= 0 and code <= 0x10FFFF and
                   not (code >= 0xD800 and code <= 0xDFFF)

  def sanitize(nil), do: ""

  def sanitize(html) when is_binary(html) do
    {:ok, content} = FastSanitize.Sanitizer.scrub(html, @default_scrubber)
    String.replace(content, "&amp;", "&")
  end

  def sanitize(_), do: ""

  def to_safe_html(content, opts \\ [])

  def to_safe_html(nil, _opts), do: ""

  def to_safe_html(content, opts) when is_binary(content) do
    format = Keyword.get(opts, :format, :html)
    emojis = Keyword.get(opts, :emojis, [])
    emoji_map = emoji_map(emojis)
    trimmed = String.trim(content)

    cond do
      trimmed == "" ->
        ""

      format == :text ->
        trimmed
        |> text_to_html(emoji_map)
        |> sanitize()

      format == :html and looks_like_html?(trimmed) ->
        trimmed
        |> emojify_html(emoji_map)
        |> sanitize()

      true ->
        trimmed
        |> text_to_html(emoji_map)
        |> sanitize()
    end
  end

  def to_safe_html(_content, _opts), do: ""

  defp looks_like_html?(content) when is_binary(content) do
    String.contains?(content, "<") and String.contains?(content, ">")
  end

  defp text_to_html(text, emoji_map) when is_binary(text) and is_map(emoji_map) do
    text =
      text
      |> String.replace("\r\n", "\n")
      |> String.replace("\r", "\n")

    text = html_unescape(text)

    "<p>" <> linkify_text(text, emoji_map) <> "</p>"
  end

  @emoji_shortcode_regex ~r/:[A-Za-z0-9_+-]{1,64}:/

  defp emojify_html(html, emoji_map) when is_binary(html) and is_map(emoji_map) do
    if map_size(emoji_map) == 0 do
      html
    else
      Regex.replace(@emoji_shortcode_regex, html, fn full ->
        shortcode = String.trim(full, ":")

        case Map.get(emoji_map, shortcode) do
          url when is_binary(url) and url != "" ->
            if safe_img_url?(url), do: emoji_img_tag(shortcode, url), else: full

          _ ->
            full
        end
      end)
    end
  end

  defp emojify_html(html, _emoji_map), do: html

  defp html_unescape(text) when is_binary(text) do
    text =
      text
      |> String.replace("&amp;", "&")
      |> String.replace("&lt;", "<")
      |> String.replace("&gt;", ">")
      |> String.replace("&quot;", "\"")
      |> String.replace("&apos;", "'")

    text =
      Regex.replace(~r/&#(\d{1,7});/, text, fn _, digits ->
        case Integer.parse(digits) do
          {codepoint, ""} when valid_codepoint(codepoint) -> <<codepoint::utf8>>
          _ -> "&#" <> digits <> ";"
        end
      end)

    Regex.replace(~r/&#x([0-9a-fA-F]{1,6});/, text, fn _, hex ->
      case Integer.parse(hex, 16) do
        {codepoint, ""} when valid_codepoint(codepoint) -> <<codepoint::utf8>>
        _ -> "&#x" <> hex <> ";"
      end
    end)
  end

  defp linkify_text(text, emoji_map) when is_binary(text) and is_map(emoji_map) do
    Regex.split(~r/(\n)/, text, include_captures: true, trim: false)
    |> Enum.map_join("", fn
      "\n" -> "<br>"
      segment -> linkify_segment(segment, emoji_map)
    end)
  end

  defp linkify_segment(segment, emoji_map) when is_binary(segment) and is_map(emoji_map) do
    Regex.split(~r/(\s+)/, segment, include_captures: true, trim: false)
    |> Enum.map_join("", fn token ->
      token
      |> linkify_token(emoji_map)
      |> IO.iodata_to_binary()
    end)
  end

  @mention_trailing ".,!?;:)]},"

  defp linkify_token(token, emoji_map) when is_binary(token) and is_map(emoji_map) do
    token = to_string(token)

    cond do
      token == "" ->
        ""

      String.starts_with?(token, "@") ->
        {core, trailing} = split_trailing_punctuation(token, @mention_trailing)

        case mention_href(core) do
          {:ok, href} -> [anchor(href, core), escape(trailing)]
          :error -> escape(token)
        end

      String.starts_with?(token, "#") ->
        {core, trailing} = split_trailing_punctuation(token, @mention_trailing)

        case hashtag_href(core) do
          {:ok, href} -> [anchor(href, core), escape(trailing)]
          :error -> escape(token)
        end

      String.starts_with?(token, ["http://", "https://"]) ->
        {core, trailing} = split_trailing_punctuation(token, @mention_trailing)

        case url_href(core) do
          {:ok, href} -> [anchor(href, core), escape(trailing)]
          :error -> escape(token)
        end

      true ->
        emojify_token(token, emoji_map)
    end
  end

  defp emojify_token(token, emoji_map) when is_binary(token) and is_map(emoji_map) do
    if map_size(emoji_map) == 0 or not String.contains?(token, ":") do
      escape(token)
    else
      parts = Regex.split(@emoji_shortcode_regex, token, include_captures: true, trim: false)

      parts
      |> Enum.map(fn part ->
        cond do
          is_binary(part) and String.starts_with?(part, ":") and String.ends_with?(part, ":") ->
            shortcode = String.trim(part, ":")

            case Map.get(emoji_map, shortcode) do
              url when is_binary(url) and url != "" ->
                if safe_img_url?(url), do: emoji_img_tag(shortcode, url), else: escape(part)

              _ ->
                escape(part)
            end

          true ->
            escape(part)
        end
      end)
    end
  end

  defp emojify_token(token, _emoji_map), do: escape(token)

  defp split_trailing_punctuation(token, chars) when is_binary(token) and is_binary(chars) do
    {trailing_chars, core_chars} =
      token
      |> String.graphemes()
      |> Enum.reverse()
      |> Enum.split_while(&String.contains?(chars, &1))

    trailing = trailing_chars |> Enum.reverse() |> Enum.join()
    core = core_chars |> Enum.reverse() |> Enum.join()
    {core, trailing}
  end

  defp mention_href("@" <> rest) when is_binary(rest) and rest != "" do
    with {:ok, nickname, host} <- parse_mention(rest),
         href when is_binary(href) <- mention_profile_href(nickname, host) do
      {:ok, href}
    else
      _ -> :error
    end
  end

  defp mention_href(_token), do: :error

  defp hashtag_href("#" <> rest) when is_binary(rest) and rest != "" do
    tag = rest

    if valid_hashtag?(tag) do
      {:ok, Endpoint.url() <> "/tags/" <> tag}
    else
      :error
    end
  end

  defp hashtag_href(_token), do: :error

  defp url_href(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        {:ok, url}

      _ ->
        :error
    end
  end

  defp url_href(_url), do: :error

  defp emoji_map(emojis) when is_list(emojis) do
    Enum.reduce(emojis, %{}, fn
      %{shortcode: shortcode, url: url}, acc when is_binary(shortcode) and is_binary(url) ->
        Map.put(acc, shortcode, url)

      %{"shortcode" => shortcode, "url" => url}, acc
      when is_binary(shortcode) and is_binary(url) ->
        Map.put(acc, shortcode, url)

      _other, acc ->
        acc
    end)
  end

  defp emoji_map(%{} = emojis), do: emojis
  defp emoji_map(_), do: %{}

  defp emoji_img_tag(shortcode, url) when is_binary(shortcode) and is_binary(url) do
    url = url |> escape_binary() |> IO.iodata_to_binary()
    shortcode = shortcode |> escape_binary() |> IO.iodata_to_binary()
    label = ":" <> shortcode <> ":"

    "<img src=\"" <>
      url <>
      "\" alt=\"" <>
      label <>
      "\" title=\"" <>
      label <>
      "\" class=\"emoji\" width=\"20\" height=\"20\">"
  end

  defp safe_img_url?(url) when is_binary(url) do
    case URI.parse(String.trim(url)) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        true

      _ ->
        false
    end
  end

  defp safe_img_url?(_url), do: false

  defp parse_mention(rest) when is_binary(rest) do
    case String.split(rest, "@", parts: 2) do
      [nickname] ->
        with true <- valid_nickname?(nickname) do
          {:ok, nickname, nil}
        else
          _ -> :error
        end

      [nickname, host] ->
        with true <- valid_nickname?(nickname),
             true <- valid_host?(host) do
          {:ok, nickname, host}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp valid_nickname?(nickname) when is_binary(nickname) do
    Regex.match?(~r/^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$/, nickname)
  end

  defp valid_nickname?(_), do: false

  defp valid_host?(host) when is_binary(host) do
    Regex.match?(~r/^[A-Za-z0-9.-]+(?::\d{1,5})?$/, host)
  end

  defp valid_host?(_), do: false

  defp valid_hashtag?(tag) when is_binary(tag) do
    Regex.match?(~r/^[\p{L}\p{N}_][\p{L}\p{N}_-]{0,63}$/u, tag)
  end

  defp valid_hashtag?(_tag), do: false

  defp mention_profile_href(nickname, nil) when is_binary(nickname),
    do: Endpoint.url() <> "/@" <> nickname

  defp mention_profile_href(nickname, host)
       when is_binary(nickname) and is_binary(host) do
    "https://" <> host <> "/@" <> nickname
  end

  defp mention_profile_href(_nickname, _host), do: nil

  defp anchor(href, label) when is_binary(href) and is_binary(label) do
    href = href |> escape_binary() |> IO.iodata_to_binary()
    label = label |> escape_binary() |> IO.iodata_to_binary()
    "<a href=\"" <> href <> "\">" <> label <> "</a>"
  end

  defp escape(value), do: escape_binary(to_string(value))

  defp escape_binary(value) when is_binary(value) do
    value
    |> Plug.HTML.html_escape_to_iodata()
  end
end
