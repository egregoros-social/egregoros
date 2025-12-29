defmodule Egregoros.HTML do
  @moduledoc false

  @default_scrubber Egregoros.HTML.Scrubber.Default

  alias EgregorosWeb.Endpoint
  alias EgregorosWeb.ProfilePaths
  alias EgregorosWeb.URL

  defguardp valid_codepoint(code)
            when is_integer(code) and code >= 0 and code <= 0x10FFFF and
                   not (code >= 0xD800 and code <= 0xDFFF)

  def sanitize(nil), do: ""

  def sanitize(html) when is_binary(html) do
    sanitize(html, FastSanitize.Sanitizer)
  end

  def sanitize(_), do: ""

  def sanitize(html, sanitizer) when is_binary(html) and is_atom(sanitizer) do
    result =
      try do
        sanitizer.scrub(html, @default_scrubber)
      rescue
        _ -> {:error, :scrub_failed}
      catch
        kind, reason -> {:error, {kind, reason}}
      end

    content =
      case result do
        {:ok, scrubbed} -> IO.iodata_to_binary(scrubbed)
        _ -> escape_html(html)
      end

    String.replace(content, "&amp;", "&")
  end

  def sanitize(_, _), do: ""

  def to_safe_html(content, opts \\ [])

  def to_safe_html(nil, _opts), do: ""

  def to_safe_html(content, opts) when is_binary(content) do
    format = Keyword.get(opts, :format, :html)
    emojis = Keyword.get(opts, :emojis, [])
    mention_hrefs = Keyword.get(opts, :mention_hrefs, %{})

    ap_tags =
      opts
      |> Keyword.get(:ap_tags, [])
      |> List.wrap()

    emoji_map = emoji_map(emojis)
    trimmed = String.trim(content)

    rendered =
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

    rewrite_mention_links(rendered, ap_tags)
  end

  def to_safe_html(_content, _opts), do: ""

  def to_safe_inline_html(content, opts \\ [])

  def to_safe_inline_html(nil, _opts), do: ""

  def to_safe_inline_html(content, opts) when is_binary(content) and is_list(opts) do
    emojis = Keyword.get(opts, :emojis, [])
    emoji_map = emoji_map(emojis)
    trimmed = String.trim(content)

    if trimmed == "" do
      ""
    else
      trimmed
      |> html_unescape()
      |> escape_html()
      |> emojify_html(emoji_map)
    end
  end

  def to_safe_inline_html(_content, _opts), do: ""

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

  defp linkify_segment(segment, emoji_map, _mention_hrefs)
       when is_binary(segment) and is_map(emoji_map) do
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

  defp linkify_token(token, emoji_map, _mention_hrefs)
       when is_binary(token) and is_map(emoji_map) do
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

  defp linkify_inline(token, emoji_map, _mention_hrefs)
       when is_binary(token) and is_map(emoji_map) do
    linkify_inline(token, emoji_map, %{})
  end

  defp linkify_inline(token, _emoji_map, _mention_hrefs), do: escape(token)

  defp linkify_match(match, mention_hrefs) when is_binary(match) and is_map(mention_hrefs) do
    cond do
      String.starts_with?(match, "@") ->
        linkify_mention(match, mention_hrefs)

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

  defp linkify_prefixed(token, href_fun, class \\ nil)
       when is_binary(token) and is_function(href_fun, 1) do
    {core, trailing} = split_trailing_punctuation(token, @mention_trailing)

    case href_fun.(core) do
      {:ok, href} -> [anchor(href, core, class), escape(trailing)]
      :error -> escape(token)
    end
  end

  defp linkify_mention(token, mention_hrefs)
       when is_binary(token) and is_map(mention_hrefs) do
    {core, trailing} = split_trailing_punctuation(token, @mention_trailing)

    case mention_href(core, mention_hrefs) do
      {:ok, href} ->
        [mention_markup(href, core), escape(trailing)]

      :error ->
        escape(token)
    end
  end

  defp linkify_mention(token, _mention_hrefs) when is_binary(token), do: escape(token)
  defp linkify_mention(_token, _mention_hrefs), do: ""

  defp mention_markup(href, "@" <> handle)
       when is_binary(href) and is_binary(handle) and handle != "" do
    href = href |> escape_binary() |> IO.iodata_to_binary()
    handle = handle |> escape_binary() |> IO.iodata_to_binary()

    "<span class=\"h-card\"><a href=\"" <>
      href <>
      "\" class=\"u-url mention mention-link\" rel=\"ugc\">@<span>" <>
      handle <>
      "</span></a></span>"
  end

  defp mention_markup(href, token) when is_binary(href) and is_binary(token) do
    token =
      token
      |> String.trim()
      |> String.trim_leading("@")

    if token == "" do
      anchor(href, token, "mention-link")
    else
      mention_markup(href, "@" <> token)
    end
  end

  defp mention_markup(_href, token) when is_binary(token), do: escape(token)
  defp mention_markup(_href, _token), do: ""

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
    case Egregoros.SafeURL.validate_http_url_no_dns(String.trim(url)) do
      :ok -> true
      _ -> false
    end
  end

  defp safe_img_url?(_url), do: false

  defp escape_html(text) when is_binary(text) do
    text
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  defp escape_html(_text), do: ""

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

  defp anchor(href, label, class)
       when is_binary(href) and is_binary(label) and is_binary(class) and class != "" do
    href = href |> escape_binary() |> IO.iodata_to_binary()
    label = label |> escape_binary() |> IO.iodata_to_binary()
    class = class |> escape_binary() |> IO.iodata_to_binary()
    "<a href=\"" <> href <> "\" class=\"" <> class <> "\">" <> label <> "</a>"
  end

  defp anchor(href, label, _class) when is_binary(href) and is_binary(label) do
    anchor(href, label)
  end

  defp escape(value), do: escape_binary(to_string(value))

  defp escape_binary(value) when is_binary(value) do
    value
    |> Plug.HTML.html_escape_to_iodata()
  end

  defp rewrite_mention_links(html, tags) when is_binary(html) and is_list(tags) do
    tags
    |> Enum.reduce(html, fn
      %{"type" => "Mention", "href" => href, "name" => name}, acc
      when is_binary(href) and href != "" and is_binary(name) and name != "" ->
        case mention_profile_path(href, name) do
          profile_path when is_binary(profile_path) and profile_path != "" ->
            profile_url = URL.absolute(profile_path)

            if is_binary(profile_url) and profile_url != "" do
              mention_candidate_hrefs(href, name)
              |> Enum.reduce(acc, fn candidate_href, html ->
                html
                |> add_anchor_class_for_href(candidate_href, "mention-link")
                |> replace_href(candidate_href, profile_url)
              end)
              |> add_anchor_class_for_href(profile_url, "mention-link")
            else
              acc
            end

          _ ->
            acc
        end

      _other, acc ->
        acc
    end)
  end

  defp rewrite_mention_links(html, _tags) when is_binary(html), do: html

  defp mention_profile_path(href, name) when is_binary(href) and is_binary(name) do
    local_domains = local_domains()

    handle =
      name
      |> String.trim()
      |> String.trim_leading("@")

    case Egregoros.Mentions.parse(handle) do
      {:ok, nickname, host} ->
        host = normalize_mention_host(host) || mention_host_from_href(href)

        nickname
        |> mention_handle_for_profile(host, local_domains)
        |> ProfilePaths.profile_path()

      :error ->
        ProfilePaths.profile_path(name) ||
          mention_profile_path_from_href(href, local_domains)
    end
  end

  defp mention_profile_path(_href, _name), do: nil

  defp mention_handle_for_profile(nickname, host, local_domains)
       when is_binary(nickname) and nickname != "" and is_list(local_domains) do
    host = normalize_mention_host(host)

    cond do
      is_binary(host) and host != "" and host in local_domains ->
        "@" <> nickname

      is_binary(host) and host != "" ->
        "@" <> nickname <> "@" <> host

      true ->
        "@" <> nickname
    end
  end

  defp mention_handle_for_profile(nickname, _host, _local_domains) when is_binary(nickname),
    do: "@" <> nickname

  defp mention_host_from_href(href) when is_binary(href) do
    href = String.trim(href)

    with %URI{host: host} = uri <- URI.parse(href),
         true <- is_binary(host) and host != "" do
      uri
      |> mention_host_from_uri()
      |> normalize_mention_host()
    else
      _ -> nil
    end
  end

  defp mention_host_from_href(_href), do: nil

  defp mention_profile_path_from_href(href, local_domains)
       when is_binary(href) and is_list(local_domains) do
    href = String.trim(href)

    with %URI{host: host, path: path} = uri <- URI.parse(href),
         true <- is_binary(host) and host != "" do
      nickname = mention_nickname_from_uri_path(path)

      host =
        uri
        |> mention_host_from_uri()
        |> normalize_mention_host()

      cond do
        nickname == "" ->
          nil

        is_binary(host) and host != "" and host in local_domains ->
          ProfilePaths.profile_path("@" <> nickname)

        is_binary(host) and host != "" ->
          ProfilePaths.profile_path("@" <> nickname <> "@" <> host)

        true ->
          ProfilePaths.profile_path("@" <> nickname)
      end
    else
      _ -> nil
    end
  end

  defp mention_profile_path_from_href(_href, _local_domains), do: nil

  defp mention_candidate_hrefs(href, name) when is_binary(href) and is_binary(name) do
    href = href |> String.trim()

    sources =
      []
      |> add_mention_source_from_name(name)
      |> add_mention_source_from_href(href)

    candidates =
      sources
      |> Enum.reduce(href_variants(href), fn {nickname, host}, acc ->
        acc ++ mention_profile_href_variants(nickname, host, href)
      end)

    candidates
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
  end

  defp mention_candidate_hrefs(href, _name) when is_binary(href),
    do: href_variants(String.trim(href))

  defp mention_candidate_hrefs(_href, _name), do: []

  defp add_mention_source_from_name(sources, name) when is_list(sources) and is_binary(name) do
    handle = name |> to_string() |> String.trim() |> String.trim_leading("@")

    case Egregoros.Mentions.parse(handle) do
      {:ok, nickname, host}
      when is_binary(nickname) and nickname != "" and is_binary(host) and host != "" ->
        [{nickname, host} | sources]

      _ ->
        sources
    end
  end

  defp add_mention_source_from_name(sources, _name) when is_list(sources), do: sources

  defp add_mention_source_from_href(sources, href) when is_list(sources) and is_binary(href) do
    with %URI{host: host, path: path} = uri <- URI.parse(href),
         true <- is_binary(host) and host != "",
         nickname when is_binary(nickname) and nickname != "" <-
           mention_nickname_from_uri_path(path),
         host <- mention_host_from_uri(uri) do
      [{nickname, host} | sources]
    else
      _ -> sources
    end
  end

  defp add_mention_source_from_href(sources, _href) when is_list(sources), do: sources

  defp mention_nickname_from_uri_path(path) when is_binary(path) do
    path
    |> String.trim("/")
    |> String.split("/", trim: true)
    |> List.last()
    |> case do
      nil -> ""
      segment -> segment |> String.trim() |> String.trim_leading("@")
    end
  end

  defp mention_nickname_from_uri_path(_path), do: ""

  defp mention_host_from_uri(%URI{host: host, port: port}) when is_binary(host) do
    cond do
      is_integer(port) and port > 0 and port not in [80, 443] ->
        host <> ":" <> Integer.to_string(port)

      true ->
        host
    end
  end

  defp mention_host_from_uri(_uri), do: ""

  defp mention_profile_href_variants(nickname, host, href)
       when is_binary(nickname) and nickname != "" and is_binary(host) and host != "" and
              is_binary(href) do
    encoded =
      nickname
      |> String.trim()
      |> URI.encode(&URI.char_unreserved?/1)

    nickname_variants = [nickname, encoded] |> Enum.reject(&(&1 == "")) |> Enum.uniq()

    scheme_variants =
      case URI.parse(href) do
        %URI{scheme: scheme} when scheme in ["http", "https"] -> [scheme, "https", "http"]
        _ -> ["https", "http"]
      end
      |> Enum.uniq()

    Enum.flat_map(scheme_variants, fn scheme ->
      base = scheme <> "://" <> host

      Enum.flat_map(nickname_variants, fn nick ->
        [
          base <> "/@" <> nick,
          base <> "/users/" <> nick
        ]
        |> Enum.flat_map(&href_variants/1)
      end)
    end)
  end

  defp mention_profile_href_variants(_nickname, _host, _href), do: []

  defp href_variants(href) when is_binary(href) do
    href = String.trim(href)

    if href == "" do
      []
    else
      trimmed = String.trim_trailing(href, "/")

      variants =
        if trimmed != href do
          [href, trimmed]
        else
          [href, href <> "/"]
        end

      variants |> Enum.reject(&(&1 == "")) |> Enum.uniq()
    end
  end

  defp href_variants(_href), do: []

  defp replace_href(html, old_href, new_href) when is_binary(html) do
    old_escaped = old_href |> escape_binary() |> IO.iodata_to_binary()
    new_escaped = new_href |> escape_binary() |> IO.iodata_to_binary()

    html
    |> String.replace("href=\"#{old_escaped}\"", "href=\"#{new_escaped}\"")
    |> String.replace("href='#{old_escaped}'", "href='#{new_escaped}'")
  end

  defp replace_href(html, _old_href, _new_href) when is_binary(html), do: html

  defp add_anchor_class_for_href(html, href, class)
       when is_binary(html) and is_binary(href) and is_binary(class) and class != "" do
    href_escaped = href |> escape_binary() |> IO.iodata_to_binary()
    href_regex = Regex.escape(href_escaped)

    Regex.replace(~r/<a\b([^>]*?)\bhref=(["'])#{href_regex}\2([^>]*?)>/, html, fn _match,
                                                                                  before,
                                                                                  quote,
                                                                                  after_attrs ->
      attrs = before <> "href=" <> quote <> href_escaped <> quote <> after_attrs
      attrs = ensure_anchor_class(attrs, class)
      "<a" <> attrs <> ">"
    end)
  end

  defp add_anchor_class_for_href(html, _href, _class) when is_binary(html), do: html

  defp ensure_anchor_class(attrs, class) when is_binary(attrs) and is_binary(class) do
    class = String.trim(class)

    if class == "" do
      attrs
    else
      case Regex.run(~r/\bclass=(["'])([^"']*)\1/, attrs) do
        nil ->
          attrs <> " class=\"" <> class <> "\""

        [full, quote, existing] ->
          tokens =
            existing
            |> String.split(~r/\s+/, trim: true)

          if class in tokens do
            attrs
          else
            updated = Enum.join(tokens ++ [class], " ")
            String.replace(attrs, full, "class=" <> quote <> updated <> quote)
          end
      end
    end
  end
end
