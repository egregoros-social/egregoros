defmodule Egregoros.HTML do
  @moduledoc false

  @default_scrubber Egregoros.HTML.Scrubber.Default

  alias EgregorosWeb.Endpoint

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
    mention_hrefs = Keyword.get(opts, :mention_hrefs, %{})
    emoji_map = emoji_map(emojis)
    trimmed = String.trim(content)

    cond do
      trimmed == "" ->
        ""

      format == :text ->
        trimmed
        |> text_to_html(emoji_map, mention_hrefs)
        |> sanitize()

      format == :html and looks_like_html?(trimmed) ->
        trimmed
        |> emojify_html(emoji_map)
        |> sanitize()

      true ->
        trimmed
        |> text_to_html(emoji_map, mention_hrefs)
        |> sanitize()
    end
  end

  def to_safe_html(_content, _opts), do: ""

  defp looks_like_html?(content) when is_binary(content) do
    String.contains?(content, "<") and String.contains?(content, ">")
  end

  defp text_to_html(text, emoji_map, mention_hrefs)
       when is_binary(text) and is_map(emoji_map) and is_map(mention_hrefs) do
    text =
      text
      |> String.replace("\r\n", "\n")
      |> String.replace("\r", "\n")

    text = html_unescape(text)

    "<p>" <> linkify_text(text, emoji_map, mention_hrefs) <> "</p>"
  end

  defp text_to_html(text, emoji_map, _mention_hrefs) when is_binary(text) and is_map(emoji_map) do
    text_to_html(text, emoji_map, %{})
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

  defp linkify_text(text, emoji_map, mention_hrefs)
       when is_binary(text) and is_map(emoji_map) and is_map(mention_hrefs) do
    Regex.split(~r/(\n)/, text, include_captures: true, trim: false)
    |> Enum.map_join("", fn
      "\n" -> "<br>"
      segment -> linkify_segment(segment, emoji_map, mention_hrefs)
    end)
  end

  defp linkify_text(text, emoji_map, _mention_hrefs) when is_binary(text) and is_map(emoji_map) do
    linkify_text(text, emoji_map, %{})
  end

  defp linkify_segment(segment, emoji_map, mention_hrefs)
       when is_binary(segment) and is_map(emoji_map) and is_map(mention_hrefs) do
    Regex.split(~r/(\s+)/, segment, include_captures: true, trim: false)
    |> Enum.map_join("", fn token ->
      token
      |> linkify_token(emoji_map, mention_hrefs)
      |> IO.iodata_to_binary()
    end)
  end

  defp linkify_segment(segment, emoji_map, _mention_hrefs) when is_binary(segment) and is_map(emoji_map) do
    linkify_segment(segment, emoji_map, %{})
  end

  @mention_trailing ".,!?;:)]},"

  @inline_link_regex ~r/(^|[\s\(\[\{\<"'.,!?;:])((?:https?:\/\/[^\s]+)|(?:@[A-Za-z0-9][A-Za-z0-9_.-]{0,63}(?:@[A-Za-z0-9.-]+(?::\d{1,5})?)?)|(?:#[\p{L}\p{N}_][\p{L}\p{N}_-]{0,63}))/u

  defp linkify_token(token, emoji_map, mention_hrefs)
       when is_binary(token) and is_map(emoji_map) and is_map(mention_hrefs) do
    token = to_string(token)

    cond do
      token == "" ->
        ""

      true ->
        linkify_inline(token, emoji_map, mention_hrefs)
    end
  end

  defp linkify_token(token, emoji_map, _mention_hrefs) when is_binary(token) and is_map(emoji_map) do
    linkify_token(token, emoji_map, %{})
  end

  defp linkify_inline(token, emoji_map, mention_hrefs)
       when is_binary(token) and is_map(emoji_map) and is_map(mention_hrefs) do
    matches = Regex.scan(@inline_link_regex, token, return: :index)

    case matches do
      [] ->
        emojify_token(token, emoji_map)

      _ ->
        {iodata, last_pos} =
          Enum.reduce(matches, {[], 0}, fn
            [_, _boundary, {start, len}], {acc, last_pos} ->
              prefix = String.slice(token, last_pos, start - last_pos)
              match = String.slice(token, start, len)

              acc = [acc, emojify_token(prefix, emoji_map), linkify_match(match, mention_hrefs)]
              {acc, start + len}

            _other, {acc, last_pos} ->
              {acc, last_pos}
          end)

        suffix = String.slice(token, last_pos, String.length(token) - last_pos)
        [iodata, emojify_token(suffix, emoji_map)]
    end
  end

  defp linkify_inline(token, emoji_map, _mention_hrefs) when is_binary(token) and is_map(emoji_map) do
    linkify_inline(token, emoji_map, %{})
  end

  defp linkify_inline(token, _emoji_map, _mention_hrefs), do: escape(token)

  defp linkify_match(match, mention_hrefs) when is_binary(match) and is_map(mention_hrefs) do
    cond do
      String.starts_with?(match, "@") ->
        linkify_prefixed(match, &mention_href(&1, mention_hrefs))

      String.starts_with?(match, "#") ->
        linkify_prefixed(match, &hashtag_href/1)

      String.starts_with?(match, ["http://", "https://"]) ->
        linkify_prefixed(match, &url_href/1)

      true ->
        escape(match)
    end
  end

  defp linkify_match(match, _mention_hrefs) when is_binary(match), do: linkify_match(match, %{})
  defp linkify_match(match, _mention_hrefs), do: escape(match)

  defp linkify_prefixed(token, href_fun) when is_binary(token) and is_function(href_fun, 1) do
    {core, trailing} = split_trailing_punctuation(token, @mention_trailing)

    case href_fun.(core) do
      {:ok, href} -> [anchor(href, core), escape(trailing)]
      :error -> escape(token)
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

  defp mention_href("@" <> rest, mention_hrefs)
       when is_binary(rest) and rest != "" and is_map(mention_hrefs) do
    with {:ok, nickname, host} <- Egregoros.Mentions.parse(rest),
         host <- normalize_mention_host(host),
         {:ok, href} <- mention_href_for(nickname, host, mention_hrefs) do
      {:ok, href}
    end
  end

  defp mention_href(_token, _mention_hrefs), do: :error

  defp mention_href_for(nickname, host, mention_hrefs)
       when is_binary(nickname) and is_map(mention_hrefs) do
    key = {nickname, host}

    case Map.get(mention_hrefs, key) do
      href when is_binary(href) and href != "" ->
        {:ok, href}

      _ ->
        case mention_profile_href(nickname, host) do
          href when is_binary(href) and href != "" -> {:ok, href}
          _ -> :error
        end
    end
  end

  defp mention_href_for(_nickname, _host, _mention_hrefs), do: :error

  defp normalize_mention_host(nil), do: nil

  defp normalize_mention_host(host) when is_binary(host) do
    host
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp normalize_mention_host(_host), do: nil

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

  defp valid_hashtag?(tag) when is_binary(tag) do
    Regex.match?(~r/^[\p{L}\p{N}_][\p{L}\p{N}_-]{0,63}$/u, tag)
  end

  defp valid_hashtag?(_tag), do: false

  defp mention_profile_href(nickname, nil) when is_binary(nickname),
    do: Endpoint.url() <> "/@" <> nickname

  defp mention_profile_href(nickname, host)
       when is_binary(nickname) and is_binary(host) do
    host = host |> String.trim() |> String.downcase()

    if host in local_domains() do
      Endpoint.url() <> "/@" <> nickname
    else
      Endpoint.url() <> "/@" <> nickname <> "@" <> host
    end
  end

  defp mention_profile_href(_nickname, _host), do: nil

  defp local_domains do
    case URI.parse(Endpoint.url()) do
      %URI{host: host} when is_binary(host) and host != "" ->
        host = String.downcase(host)

        domains =
          case URI.parse(Endpoint.url()) do
            %URI{port: port} when is_integer(port) and port > 0 ->
              [host, host <> ":" <> Integer.to_string(port)]

            _ ->
              [host]
          end

        Enum.uniq(domains)

      _ ->
        []
    end
  end

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
