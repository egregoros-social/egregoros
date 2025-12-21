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

  test "renders custom emoji reactions present on the entry" do
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
          attachments: [],
          liked?: false,
          likes_count: 0,
          reposted?: false,
          reposts_count: 0,
          reactions: %{
            "🔥" => %{count: 0, reacted?: false},
            "😀" => %{count: 1, reacted?: true}
          }
        }
      })

    assert html =~ ~s(data-role="reaction")
    assert html =~ ~s(data-emoji="😀")
  end

  test "renders video attachments with a video tag" do
    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: %{id: 1},
        entry: %{
          object: %{
            id: 1,
            inserted_at: ~U[2025-01-01 00:00:00Z],
            local: false,
            data: %{"content" => "<p>Hello</p>"}
          },
          actor: %{
            display_name: "Alice",
            handle: "@alice",
            avatar_url: nil
          },
          attachments: [
            %{href: "/uploads/media/1/video.mp4", description: "", media_type: "video/mp4"}
          ],
          liked?: false,
          likes_count: 0,
          reposted?: false,
          reposts_count: 0,
          reactions: %{}
        }
      })

    assert html =~ "<video"
    assert html =~ ~s(src="/uploads/media/1/video.mp4")
    assert html =~ ~s(type="video/mp4")
  end

  test "renders video attachments even when the media type is wrong" do
    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: %{id: 1},
        entry: %{
          object: %{
            id: 1,
            inserted_at: ~U[2025-01-01 00:00:00Z],
            local: false,
            data: %{"content" => "<p>Hello</p>"}
          },
          actor: %{
            display_name: "Alice",
            handle: "@alice",
            avatar_url: nil
          },
          attachments: [
            %{href: "/uploads/media/1/video.mp4", description: "", media_type: "image/png"}
          ],
          liked?: false,
          likes_count: 0,
          reposted?: false,
          reposts_count: 0,
          reactions: %{}
        }
      })

    assert html =~ "<video"
    assert html =~ ~s(src="/uploads/media/1/video.mp4")
  end

  test "renders non-media attachments as links" do
    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: %{id: 1},
        entry: %{
          object: %{
            id: 1,
            inserted_at: ~U[2025-01-01 00:00:00Z],
            local: false,
            data: %{"content" => "<p>Hello</p>"}
          },
          actor: %{
            display_name: "Alice",
            handle: "@alice",
            avatar_url: nil
          },
          attachments: [
            %{
              href: "/uploads/media/1/file.pdf",
              description: "PDF",
              media_type: "application/pdf"
            }
          ],
          liked?: false,
          likes_count: 0,
          reposted?: false,
          reposts_count: 0,
          reactions: %{}
        }
      })

    assert html =~ ~s(data-kind="link")
    assert html =~ ~s(href="/uploads/media/1/file.pdf")
  end

  test "renders image attachments as media viewer buttons" do
    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: nil,
        entry: %{
          object: %{
            id: 1,
            inserted_at: ~U[2025-01-01 00:00:00Z],
            local: false,
            data: %{"content" => "<p>Hello</p>"}
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
          reactions: %{}
        }
      })

    assert html =~ ~s(data-role="attachment-open")
    assert html =~ ~s(predux:media-open)
    assert html =~ ~s(#media-viewer)
    refute html =~ ~s(open_media)
    refute html =~ ~s(phx-value-id="1")
    refute html =~ ~s(phx-value-index="0")
  end

  test "links actor to the profile page when nickname is present" do
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
            nickname: "alice",
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

    assert html =~ ~s(href="/@alice")
    assert html =~ ~s(data-role="actor-link")
  end

  test "links remote actors to domain-qualified profile pages" do
    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: nil,
        entry: %{
          object: %{
            id: 1,
            inserted_at: ~U[2025-01-01 00:00:00Z],
            local: false,
            data: %{"content" => "<p>Hello world</p>"}
          },
          actor: %{
            display_name: "Lain",
            nickname: "lain",
            handle: "@lain@lain.com",
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

    assert html =~ ~s(href="/@lain@lain.com")
    assert html =~ ~s(data-role="actor-link")
  end

  test "does not link actor when handle is missing" do
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
            handle: nil,
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

    refute html =~ ~s(data-role="actor-link")
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

  test "links the timestamp to a local status permalink when available" do
    uuid = "8a31b5d5-5453-4f65-88b9-e0b8d535a4b4"
    ap_id = PleromaReduxWeb.Endpoint.url() <> "/objects/" <> uuid

    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: nil,
        entry: %{
          object: %{
            id: 1,
            ap_id: ap_id,
            inserted_at: ~U[2025-01-01 00:00:00Z],
            local: true,
            data: %{"content" => "Hello world"}
          },
          actor: %{
            display_name: "Alice",
            nickname: "alice",
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

    assert html =~ ~s(data-role="post-permalink")
    assert html =~ ~s(href="/@alice/#{uuid}")
  end

  test "renders a status action menu with a copy-link target" do
    uuid = "8a31b5d5-5453-4f65-88b9-e0b8d535a4b4"
    permalink = PleromaReduxWeb.Endpoint.url() <> "/@alice/#{uuid}"
    ap_id = PleromaReduxWeb.Endpoint.url() <> "/objects/" <> uuid

    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: %{id: 1},
        entry: %{
          object: %{
            id: 1,
            ap_id: ap_id,
            inserted_at: ~U[2025-01-01 00:00:00Z],
            local: true,
            data: %{"content" => "Hello world"}
          },
          actor: %{
            display_name: "Alice",
            nickname: "alice",
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

    assert html =~ ~s(data-role="status-menu")
    assert html =~ ~s(data-role="copy-link")
    assert html =~ ~s(data-copy-text="#{permalink}")
  end

  test "renders a reply action that links to the status page" do
    uuid = "8a31b5d5-5453-4f65-88b9-e0b8d535a4b4"
    ap_id = PleromaReduxWeb.Endpoint.url() <> "/objects/" <> uuid

    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: %{id: 1},
        entry: %{
          object: %{
            id: 1,
            ap_id: ap_id,
            inserted_at: ~U[2025-01-01 00:00:00Z],
            local: true,
            data: %{"content" => "Hello world"}
          },
          actor: %{
            display_name: "Alice",
            nickname: "alice",
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

    assert html =~ ~s(data-role="reply")
    assert html =~ ~s(href="/@alice/#{uuid}?reply=true#reply-form")
  end

  test "renders content warnings as a toggle and keeps the post content inside it" do
    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: nil,
        entry: %{
          object: %{
            id: 1,
            inserted_at: ~U[2025-01-01 00:00:00Z],
            local: true,
            data: %{"summary" => "Spoilers", "content" => "Hello world"}
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

    assert html =~ ~s(data-role="content-warning")
    assert html =~ "Spoilers"
    assert html =~ "Hello world"
  end

  test "hides sensitive media behind a reveal button" do
    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: nil,
        entry: %{
          object: %{
            id: 1,
            inserted_at: ~U[2025-01-01 00:00:00Z],
            local: true,
            data: %{"content" => "Hello world", "sensitive" => true}
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
          reactions: %{}
        }
      })

    assert html =~ ~s(data-role="sensitive-media-reveal")
    assert html =~ ~s(id="attachments-1")
    assert html =~ ~r/id="attachments-1"[^>]*class="[^"]*hidden/
  end

  test "collapses long content behind a show-more toggle" do
    long_content = String.duplicate("a", 600)

    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: nil,
        entry: %{
          object: %{
            id: 1,
            inserted_at: ~U[2025-01-01 00:00:00Z],
            local: true,
            data: %{"content" => long_content}
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

    assert html =~ ~s(data-role="post-content-toggle")
    assert html =~ ~r/id="post-content-1"[^>]*class="[^"]*max-h-64/
    assert html =~ ~r/id="post-content-1"[^>]*class="[^"]*overflow-hidden/
  end

  test "does not expose unsafe remote ids as share urls" do
    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: %{id: 1},
        entry: %{
          object: %{
            id: 1,
            ap_id: "javascript:alert(1)",
            inserted_at: ~U[2025-01-01 00:00:00Z],
            local: false,
            data: %{"content" => "<p>Hello</p>"}
          },
          actor: %{
            display_name: "Alice",
            handle: "@alice@remote.example",
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

    assert html =~ ~s(data-role="status-menu")
    refute html =~ ~s(data-role="copy-link")
    refute html =~ ~s(data-role="open-link")
  end
end
