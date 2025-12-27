defmodule Egregoros.HTMLTest do
  use ExUnit.Case, async: true

  import Mox

  alias Egregoros.HTML

  setup :set_mox_from_context
  setup :verify_on_exit!

  describe "sanitize/1" do
    test "removes script tags" do
      html = "<p>ok</p><script>alert(1)</script>"

      scrubbed = HTML.sanitize(html)

      assert scrubbed =~ "ok"
      refute scrubbed =~ "<script"
    end

    test "removes event handler attributes" do
      html = "<p onclick=\"alert(1)\">ok</p>"

      scrubbed = HTML.sanitize(html)

      assert scrubbed =~ "ok"
      refute scrubbed =~ "onclick="
      refute scrubbed =~ "alert(1)"
    end

    test "rejects javascript: hrefs" do
      html = "<a href=\"javascript:alert(1)\">x</a>"

      scrubbed = HTML.sanitize(html)

      assert scrubbed =~ ">x<"
      refute scrubbed =~ "javascript:"
    end

    test "adds safe rel attributes to links" do
      html = "<a href=\"https://example.com\">x</a>"

      scrubbed = HTML.sanitize(html)

      assert scrubbed =~ "nofollow"
      assert scrubbed =~ "noopener"
      assert scrubbed =~ "noreferrer"
    end

    test "preserves existing rel values while adding required ones" do
      html = "<a href=\"https://example.com\" rel=\"me\">x</a>"

      scrubbed = HTML.sanitize(html)

      assert scrubbed =~ "rel="
      assert scrubbed =~ "me"
      assert scrubbed =~ "nofollow"
      assert scrubbed =~ "noopener"
      assert scrubbed =~ "noreferrer"
    end

    test "does not duplicate required rel values (case-insensitive)" do
      html = "<a href=\"https://example.com\" rel=\"NOFOLLOW noopener\">x</a>"

      scrubbed = HTML.sanitize(html)

      assert [_, rel] = Regex.run(~r/rel="([^"]+)"/, scrubbed)

      tokens =
        rel
        |> String.split(~r/\s+/, trim: true)
        |> Enum.map(&String.downcase/1)

      assert Enum.uniq(tokens) == tokens
      assert "nofollow" in tokens
      assert "noopener" in tokens
      assert "noreferrer" in tokens
    end

    test "preserves allowed attributes on links" do
      html = "<a href=\"https://example.com\" class=\"mention\" title=\"hello\">x</a>"

      scrubbed = HTML.sanitize(html)

      assert scrubbed =~ ~s(class="mention")
      assert scrubbed =~ ~s(title="hello")
    end

    test "only allows safe target values on links" do
      html = "<a href=\"https://example.com\" target=\"_blank\">x</a>"

      scrubbed = HTML.sanitize(html)

      assert scrubbed =~ ~s(target="_blank")

      scrubbed = HTML.sanitize("<a href=\"https://example.com\" target=\"evil\">x</a>")
      refute scrubbed =~ ~s(target="evil")
    end

    test "removes disallowed tags like iframe" do
      html = "<p>ok</p><iframe src=\"https://evil.example/\"></iframe>"

      scrubbed = HTML.sanitize(html)

      assert scrubbed =~ "ok"
      refute scrubbed =~ "<iframe"
    end

    test "removes html comments" do
      html = "<p>ok</p><!-- secret --><p>more</p>"

      scrubbed = HTML.sanitize(html)

      assert scrubbed =~ "<p>ok</p>"
      assert scrubbed =~ "<p>more</p>"
      refute scrubbed =~ "<!--"
      refute scrubbed =~ "secret"
    end

    test "allows basic formatting tags" do
      html = "<p>hello <strong>bold</strong> <em>em</em> <u>u</u> <s>s</s></p>"

      scrubbed = HTML.sanitize(html)

      assert scrubbed =~ "<strong>bold</strong>"
      assert scrubbed =~ "<em>em</em>"
      assert scrubbed =~ "<u>u</u>"
      assert scrubbed =~ "<s>s</s>"
    end

    test "allows code blocks with classes" do
      html =
        "<pre class=\"highlight\"><code class=\"language-elixir\">IO.puts(1)</code></pre>"

      scrubbed = HTML.sanitize(html)

      assert scrubbed =~ "<pre"
      assert scrubbed =~ ~s(class="highlight")
      assert scrubbed =~ "<code"
      assert scrubbed =~ ~s(class="language-elixir")
      assert scrubbed =~ "IO.puts"
    end

    test "allows lists with classes" do
      html = "<ul class=\"list\"><li class=\"item\">one</li><li>two</li></ul>"

      scrubbed = HTML.sanitize(html)

      assert scrubbed =~ "<ul"
      assert scrubbed =~ ~s(class="list")
      assert scrubbed =~ "<li"
      assert scrubbed =~ ~s(class="item")
      assert scrubbed =~ ">one<"
      assert scrubbed =~ ">two<"
    end

    test "allows span and blockquote classes and strips event handlers" do
      html =
        "<blockquote class=\"quote\"><span class=\"mention\" onclick=\"alert(1)\">@alice</span></blockquote>"

      scrubbed = HTML.sanitize(html)

      assert scrubbed =~ "<blockquote"
      assert scrubbed =~ ~s(class="quote")
      assert scrubbed =~ "<span"
      assert scrubbed =~ ~s(class="mention")
      assert scrubbed =~ "@alice"
      refute scrubbed =~ "onclick="
      refute scrubbed =~ "alert(1)"
    end

    test "allows img tags with http(s) src" do
      html = "<p>ok</p><img src=\"https://cdn.example/emoji.png\" alt=\":blob:\" class=\"emoji\">"

      scrubbed = HTML.sanitize(html)

      assert scrubbed =~ "<img"
      assert scrubbed =~ "src=\"https://cdn.example/emoji.png\""
    end

    test "preserves allowed img dimension attributes" do
      html = "<img src=\"https://cdn.example/x.png\" width=\"100\" height=\"50\">"

      scrubbed = HTML.sanitize(html)

      assert scrubbed =~ "<img"
      assert scrubbed =~ ~s(width="100")
      assert scrubbed =~ ~s(height="50")
    end

    test "removes event handler attributes from img tags" do
      html =
        "<img src=\"https://cdn.example/x.png\" onerror=\"alert(1)\" alt=\"x\" class=\"emoji\">"

      scrubbed = HTML.sanitize(html)

      assert scrubbed =~ "src=\"https://cdn.example/x.png\""
      refute scrubbed =~ "onerror="
      refute scrubbed =~ "alert(1)"
    end

    test "rejects javascript: src on img tags" do
      html = "<img src=\"javascript:alert(1)\" alt=\"x\" class=\"emoji\">"

      scrubbed = HTML.sanitize(html)

      refute scrubbed =~ "javascript:"
      refute scrubbed =~ "alert(1)"
    end

    test "falls back to escaping when scrub fails" do
      Egregoros.HTML.Sanitizer.Mock
      |> expect(:scrub, fn _html, _scrubber -> {:error, :boom} end)

      scrubbed =
        HTML.sanitize("<p>ok</p><script>alert(1)</script>", Egregoros.HTML.Sanitizer.Mock)

      assert scrubbed =~ "&lt;p&gt;ok&lt;/p&gt;"
      refute scrubbed =~ "<script"
    end

    test "falls back to escaping when scrub raises" do
      Egregoros.HTML.Sanitizer.Mock
      |> expect(:scrub, fn _html, _scrubber -> raise "boom" end)

      scrubbed = HTML.sanitize("<p>ok</p>", Egregoros.HTML.Sanitizer.Mock)

      assert scrubbed =~ "&lt;p&gt;ok&lt;/p&gt;"
    end
  end

  describe "to_safe_html/2" do
    test "renders plain text as escaped html" do
      assert HTML.to_safe_html("<script>alert(1)</script>", format: :text) =~
               "&lt;script&gt;alert(1)&lt;/script&gt;"
    end

    test "wraps plain text in a paragraph" do
      assert HTML.to_safe_html("hello", format: :text) =~ "<p>hello</p>"
    end

    test "converts newlines to br" do
      assert HTML.to_safe_html("hello\nworld", format: :text) =~ "<br"
    end

    test "sanitizes html input" do
      safe = HTML.to_safe_html("<p>ok</p><script>alert(1)</script>", format: :html)
      assert safe =~ "<p>ok</p>"
      refute safe =~ "<script"
    end

    test "doesn't double-escape existing entities when converting to html" do
      safe = HTML.to_safe_html("there&#39;s", format: :html)
      assert safe =~ "there&#39;s"
      refute safe =~ "there&amp;#39;s"

      safe = HTML.to_safe_html("there&apos;s", format: :html)
      assert safe =~ "there&#39;s"
      refute safe =~ "there&amp;apos;"
    end

    test "unescapes double-escaped entities in html input" do
      safe = HTML.to_safe_html("<p>there&amp;#39;s</p>", format: :html)
      assert safe =~ ~r/there(&#39;|&apos;|')s/
      refute safe =~ "there&amp;#39;s"

      safe = HTML.to_safe_html("<p>there&amp;apos;s</p>", format: :html)
      assert safe =~ ~r/there(&#39;|&apos;|')s/
      refute safe =~ "there&amp;apos;"
    end

    test "preserves text like <3 when entities are present" do
      safe = HTML.to_safe_html("I&#39;m <3", format: :html)
      assert safe =~ "I&#39;m"
      assert safe =~ "&lt;3"
    end

    test "linkifies local @mentions in plain text" do
      safe = HTML.to_safe_html("hi @alice", format: :text)
      assert safe =~ ~s(href="#{EgregorosWeb.Endpoint.url()}/@alice")
      assert safe =~ ">@alice</a>"
    end

    test "linkifies remote @mentions in plain text" do
      safe = HTML.to_safe_html("hi @bob@example.com", format: :text)
      assert safe =~ ~s(href="#{EgregorosWeb.Endpoint.url()}/@bob@example.com")
      assert safe =~ ">@bob@example.com</a>"
    end

    test "does not linkify email addresses" do
      safe = HTML.to_safe_html("contact alice@example.com", format: :text)
      refute safe =~ "<a "
    end

    test "keeps trailing punctuation outside mention links" do
      safe = HTML.to_safe_html("hi @alice,", format: :text)
      assert safe =~ ">@alice</a>,"
    end

    test "linkifies @mentions inside surrounding punctuation" do
      safe = HTML.to_safe_html("hi (@alice)", format: :text)

      assert safe =~ "(<a "
      assert safe =~ ~s(href="#{EgregorosWeb.Endpoint.url()}/@alice")
      assert safe =~ ">@alice</a>)"
    end

    test "linkifies multiple @mentions inside the same token" do
      safe = HTML.to_safe_html("hi (@alice,@bob@example.com)", format: :text)

      assert safe =~ "(<a "
      assert safe =~ ~s(href="#{EgregorosWeb.Endpoint.url()}/@alice")
      assert safe =~ ">@alice</a>,<a"
      assert safe =~ ~s(href="#{EgregorosWeb.Endpoint.url()}/@bob@example.com")
      assert safe =~ ">@bob@example.com</a>)"
    end

    test "linkifies hashtags in plain text" do
      safe = HTML.to_safe_html("hi #elixir", format: :text)
      assert safe =~ ~s(href="#{EgregorosWeb.Endpoint.url()}/tags/elixir")
      assert safe =~ ">#elixir</a>"
    end

    test "keeps trailing punctuation outside hashtag links" do
      safe = HTML.to_safe_html("hi #elixir,", format: :text)
      assert safe =~ ">#elixir</a>,"
    end

    test "linkifies http(s) urls in plain text" do
      safe = HTML.to_safe_html("see https://example.com/path", format: :text)
      assert safe =~ ~s(href="https://example.com/path")
      assert safe =~ ">https://example.com/path</a>"
    end

    test "keeps trailing punctuation outside url links" do
      safe = HTML.to_safe_html("see https://example.com).", format: :text)
      assert safe =~ ~s(href="https://example.com")
      assert safe =~ ">https://example.com</a>)."
    end

    test "linkifies urls inside surrounding punctuation" do
      safe = HTML.to_safe_html("see (https://example.com)", format: :text)
      assert safe =~ "(<a "
      assert safe =~ ~s(href="https://example.com")
      assert safe =~ ">https://example.com</a>)"
    end

    test "does not linkify non-http urls in plain text" do
      safe = HTML.to_safe_html("see javascript:alert(1)", format: :text)
      refute safe =~ "<a "
      assert safe =~ "javascript:alert(1)"
    end

    test "replaces custom emoji shortcodes in plain text when tags are provided" do
      safe =
        HTML.to_safe_html("hi :shrug:",
          format: :text,
          emojis: [%{shortcode: "shrug", url: "https://cdn.example/shrug.png"}]
        )

      assert safe =~ "<img"
      assert safe =~ "src=\"https://cdn.example/shrug.png\""
      assert safe =~ "alt=\":shrug:\""
    end

    test "replaces custom emoji shortcodes in html input when tags are provided" do
      safe =
        HTML.to_safe_html("<p>hi :shrug:</p>",
          format: :html,
          emojis: [%{shortcode: "shrug", url: "https://cdn.example/shrug.png"}]
        )

      assert safe =~ "<p>hi"
      assert safe =~ "<img"
      assert safe =~ "src=\"https://cdn.example/shrug.png\""
    end

    test "does not render custom emojis with unsafe urls" do
      safe =
        HTML.to_safe_html("hi :shrug:",
          format: :text,
          emojis: [%{shortcode: "shrug", url: "javascript:alert(1)"}]
        )

      refute safe =~ "<img"
      assert safe =~ ":shrug:"
    end

    test "does not render custom emojis with localhost or private ip urls" do
      safe =
        HTML.to_safe_html("hi :shrug:",
          format: :text,
          emojis: [%{shortcode: "shrug", url: "http://localhost/emoji.png"}]
        )

      refute safe =~ "<img"
      assert safe =~ ":shrug:"

      safe =
        HTML.to_safe_html("hi :shrug:",
          format: :text,
          emojis: [%{shortcode: "shrug", url: "http://127.0.0.1/emoji.png"}]
        )

      refute safe =~ "<img"
      assert safe =~ ":shrug:"
    end
  end
end
