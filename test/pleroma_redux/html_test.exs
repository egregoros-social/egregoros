defmodule PleromaRedux.HTMLTest do
  use ExUnit.Case, async: true

  alias PleromaRedux.HTML

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

    test "removes disallowed tags like iframe" do
      html = "<p>ok</p><iframe src=\"https://evil.example/\"></iframe>"

      scrubbed = HTML.sanitize(html)

      assert scrubbed =~ "ok"
      refute scrubbed =~ "<iframe"
    end

    test "allows img tags with http(s) src" do
      html = "<p>ok</p><img src=\"https://cdn.example/emoji.png\" alt=\":blob:\" class=\"emoji\">"

      scrubbed = HTML.sanitize(html)

      assert scrubbed =~ "<img"
      assert scrubbed =~ "src=\"https://cdn.example/emoji.png\""
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
  end
end
