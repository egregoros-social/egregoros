defmodule EgregorosWeb.Components.Shared.ContentBodyTest do
  use EgregorosWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias EgregorosWeb.Components.Shared.ContentBody

  test "renders legacy egregoros:e2ee_dm payloads as plain content without unlock UI" do
    html =
      render_component(&ContentBody.content_body/1, %{
        id: "post-1",
        object: %{
          local: true,
          data: %{
            "content" => "Secret",
            "egregoros:e2ee_dm" => %{"ciphertext" => "abc"}
          }
        }
      })

    assert html =~ "Secret"
    refute html =~ "E2EEDMMessage"
    refute html =~ "e2ee-dm-body"
    refute html =~ "e2ee-dm-unlock"
    refute html =~ "data-e2ee-dm"
    refute html =~ "data-current-user-ap-id"
  end

  test "collapses long remote HTML content behind a show-more toggle" do
    long_text = String.duplicate("a", 600)

    html =
      render_component(&ContentBody.content_body/1, %{
        id: "post-1",
        object: %{
          local: false,
          data: %{
            "content" => "<p>#{long_text}</p>"
          }
        }
      })

    assert html =~ ~s(data-role="post-content-toggle")
    assert html =~ ~s(id="post-content-post-1")
    assert html =~ ~s(max-h-64)
    assert html =~ ~s(overflow-hidden)
  end
end
