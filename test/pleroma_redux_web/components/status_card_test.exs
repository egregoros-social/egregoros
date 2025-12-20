defmodule PleromaReduxWeb.StatusCardTest do
  use PleromaReduxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PleromaReduxWeb.StatusCard

  test "renders a post with attachments and actions" do
    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: %{id: 1},
        entry: %{
          object: %{
            id: 1,
            inserted_at: ~U[2025-01-01 00:00:00Z],
            local: true,
            data: %{"content" => "Hello world"}
          },
          actor: %{
            display_name: "Alice",
            handle: "@alice",
            avatar_url: nil
          },
          attachments: [
            %{href: "/uploads/media/1/photo.png", description: "Alt", media_type: "image/png"}
          ],
          liked?: false,
          likes_count: 0,
          reposted?: false,
          reposts_count: 0,
          reactions: %{"🔥" => %{count: 0, reacted?: false}}
        }
      })

    assert html =~ ~s(id="post-1")
    assert html =~ ~s(data-role="status-card")
    assert html =~ ~s(data-role="attachments")
    assert html =~ ~s(data-role="like")
    assert html =~ ~s(data-role="repost")
    assert html =~ ~s(data-role="reaction")
  end

  test "hides actions for signed-out visitors" do
    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: nil,
        entry: %{
          object: %{
            id: 1,
            inserted_at: ~U[2025-01-01 00:00:00Z],
            local: true,
            data: %{"content" => "Hello world"}
          },
          actor: %{
            display_name: "Alice",
            handle: "@alice",
            avatar_url: nil
          },
          attachments: [],
          liked?: false,
          likes_count: 0,
          reposted?: false,
          reposts_count: 0,
          reactions: %{}
        }
      })

    refute html =~ ~s(data-role="like")
    refute html =~ ~s(data-role="repost")
    refute html =~ ~s(data-role="reaction")
  end
end
