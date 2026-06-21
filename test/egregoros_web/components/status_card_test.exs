defmodule EgregorosWeb.StatusCardTest do
  use EgregorosWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias EgregorosWeb.StatusCard

  test "renders a post with attachments and actions" do
    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: %{id: "1"},
        entry: %{
          object: %{
            id: "1",
            type: "Note",
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
        current_user: %{id: "1"},
        entry: %{
          object: %{
            id: "1",
            type: "Note",
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

  test "renders a reaction picker hook for adding more emoji reactions" do
    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: %{id: "1"},
        entry: %{
          object: %{
            id: "1",
            type: "Note",
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
          reactions: %{"🔥" => %{count: 0, reacted?: false}}
        }
      })

    assert html =~ ~s(data-role="reaction-picker")
    assert html =~ ~s(phx-hook="ReactionPicker")
    assert html =~ ~s(data-post-id="1")
    assert html =~ ~s(data-feed-id="1")
    assert html =~ ~s(data-role="reaction-picker-toggle")
    assert html =~ ~s(data-role="reaction-picker-menu")
    assert html =~ ~s(data-role="reaction-picker-grid")
    refute html =~ ~s(data-role="reaction-picker-option")

    assert html =~
             ~r/id="reaction-picker-post-1".*shadow-\[4px_4px_0_var\(--border-default\)\]/s
  end

  test "renders badge cards for verifiable credentials with interactions" do
    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-badge-1",
        current_user: %{id: "1"},
        entry: %{
          object: %{
            id: "badge-1",
            type: "VerifiableCredential",
            inserted_at: ~U[2025-01-01 00:00:00Z],
            local: true,
            data: %{"id" => "badge-1", "type" => "VerifiableCredential"}
          },
          actor: %{
            display_name: "Issuer",
            handle: "@issuer",
            avatar_url: nil
          },
          badge: %{
            title: "Donator",
            description: "Awarded for supporting.",
            image_url: "https://cdn.example/badges/donator.png",
            validity: "Valid",
            valid_range: "Jan 1, 2025 - Jan 1, 2026",
            recipient: %{display_name: "Recipient", handle: "@recipient"},
            badge_path: "/@recipient/badges/badge-1"
          },
          liked?: false,
          likes_count: 0,
          reposted?: false,
          reposts_count: 0,
          reactions: %{}
        }
      })

    assert html =~ ~s(data-item="badge-card")
    assert html =~ ~s(data-role="like")
    assert html =~ ~s(data-role="repost")
    assert html =~ ~s(data-role="reaction")
    assert html =~ "Donator"
  end

  test "badge cards show issuer ap id and do not link the actor" do
    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-badge-issuer-1",
        current_user: %{id: "1"},
        entry: %{
          object: %{
            id: "badge-issuer-1",
            type: "VerifiableCredential",
            inserted_at: ~U[2025-01-01 00:00:00Z],
            local: true,
            data: %{"id" => "badge-issuer-1", "type" => "VerifiableCredential"}
          },
          actor: %{
            display_name: "Issuer",
            handle: "@issuer",
            avatar_url: nil
          },
          badge: %{
            title: "Donator",
            description: "Awarded for supporting.",
            image_url: "https://cdn.example/badges/donator.png",
            validity: "Valid",
            valid_range: "Jan 1, 2025 - Jan 1, 2026",
            issuer_ap_id: "https://example.com",
            recipient: %{display_name: "Recipient", handle: "@recipient"},
            badge_path: "/@recipient/badges/badge-issuer-1"
          },
          liked?: false,
          likes_count: 0,
          reposted?: false,
          reposts_count: 0,
          reactions: %{}
        }
      })

    assert html =~ ~s(data-item="badge-card")
    assert html =~ ~r/data-role="post-actor-handle"[^>]*>\s*https:\/\/example\.com\s*</
    refute html =~ ~s(data-role="actor-link")
  end

  test "renders a reply link when permalinks are available" do
    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: %{id: "1"},
        reply_mode: :navigate,
        entry: %{
          object: %{
            id: "1",
            ap_id: "http://localhost:4000/objects/uuid-1",
            type: "Note",
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
          reactions: %{"🔥" => %{count: 0, reacted?: false}}
        }
      })

    assert html =~ ~s(href="/@alice/uuid-1?reply=true#reply-form")
  end

  test "renders custom emojis in post content when ActivityPub emoji tags are present" do
    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: %{id: "1"},
        entry: %{
          object: %{
            id: "1",
            type: "Note",
            inserted_at: ~U[2025-01-01 00:00:00Z],
            local: false,
            data: %{
              "content" => "<p>hi :shrug:</p>",
              "tag" => [
                %{
                  "type" => "Emoji",
                  "name" => ":shrug:",
                  "icon" => %{"url" => "https://cdn.example/shrug.png"}
                }
              ]
            }
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
          reactions: %{"🔥" => %{count: 0, reacted?: false}}
        }
      })

    assert html =~ "src=\"https://cdn.example/shrug.png\""
    assert html =~ "alt=\":shrug:\""
  end

  test "styles links inside post bodies" do
    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: %{id: "1"},
        entry: %{
          object: %{
            id: "1",
            type: "Note",
            inserted_at: ~U[2025-01-01 00:00:00Z],
            local: true,
            data: %{"content" => "Check this out https://example.com"}
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

    assert html =~ ~s(href="https://example.com")
    assert html =~ ~s(data-role="post-content")
    assert html =~ "[&amp;_a]:underline"
  end

  test "renders video attachments with a video tag" do
    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: %{id: "1"},
        entry: %{
          object: %{
            id: "1",
            type: "Note",
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
        current_user: %{id: "1"},
        entry: %{
          object: %{
            id: "1",
            type: "Note",
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

  test "renders audio attachments with CORS-enabled audio tag" do
    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: %{id: "1"},
        entry: %{
          object: %{
            id: "1",
            type: "Note",
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
            %{href: "/uploads/media/1/audio.mp3", description: "", media_type: "audio/mpeg"}
          ],
          liked?: false,
          likes_count: 0,
          reposted?: false,
          reposts_count: 0,
          reactions: %{}
        }
      })

    assert html =~ "<audio"
    assert html =~ ~s(crossorigin="anonymous")
    assert html =~ ~s(src="/uploads/media/1/audio.mp3")
    assert html =~ ~s(type="audio/mpeg")
  end

  test "renders non-media attachments as links" do
    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: %{id: "1"},
        entry: %{
          object: %{
            id: "1",
            type: "Note",
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
    assert html =~ ~s(rel="nofollow noopener noreferrer")
  end

  test "renders image attachments as media viewer buttons" do
    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: nil,
        entry: %{
          object: %{
            id: "1",
            type: "Note",
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
    assert html =~ ~s(egregoros:media-open)
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
            id: "1",
            type: "Note",
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
            id: "1",
            type: "Note",
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
            id: "1",
            type: "Note",
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
            id: "1",
            type: "Note",
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
    ap_id = EgregorosWeb.Endpoint.url() <> "/objects/" <> uuid

    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: nil,
        entry: %{
          object: %{
            id: "1",
            type: "Note",
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

  test "prefers the status published timestamp for display over ingestion order" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    published = DateTime.add(now, -2 * 365 * 24 * 60 * 60, :second)

    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: nil,
        entry: %{
          object: %{
            id: "1",
            type: "Note",
            inserted_at: now,
            published: published,
            local: false,
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

    assert html =~ ~r/>\s*2y\s*</
    refute html =~ ~r/>\s*now\s*</
  end

  test "renders a status action menu with a copy-link target" do
    uuid = "8a31b5d5-5453-4f65-88b9-e0b8d535a4b4"
    permalink = EgregorosWeb.Endpoint.url() <> "/@alice/#{uuid}"
    ap_id = EgregorosWeb.Endpoint.url() <> "/objects/" <> uuid

    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: %{id: "1"},
        entry: %{
          object: %{
            id: "1",
            type: "Note",
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
    assert html =~ ~s(data-role="status-menu-trigger")
    assert html =~ ~s(aria-label="Post actions")
    assert html =~ ~s(phx-click-away=)
    assert html =~ ~s(phx-window-keydown=)
    assert html =~ ~s(phx-key="escape")
    assert html =~ ~r/id="post-1-menu".*shadow-\[4px_4px_0_var\(--border-default\)\]/s
    assert html =~ ~s(data-role="copy-link")
    assert html =~ ~s(data-copy-text="#{permalink}")
  end

  test "renders a reply action that links to the status page" do
    uuid = "8a31b5d5-5453-4f65-88b9-e0b8d535a4b4"
    ap_id = EgregorosWeb.Endpoint.url() <> "/objects/" <> uuid

    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: %{id: "1"},
        entry: %{
          object: %{
            id: "1",
            type: "Note",
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

  test "renders a reply action for remote statuses that links to the local status page" do
    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-123",
        current_user: %{id: "1"},
        entry: %{
          object: %{
            id: "123",
            type: "Note",
            ap_id: "https://remote.example/objects/123",
            inserted_at: ~U[2025-01-01 00:00:00Z],
            local: false,
            data: %{"content" => "<p>Hello world</p>"}
          },
          actor: %{
            display_name: "Bob",
            nickname: "bob",
            handle: "@bob@remote.example",
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
    assert html =~ ~s(href="/@bob@remote.example/123?reply=true#reply-form")
  end

  test "renders content warnings as a toggle and keeps the post content inside it" do
    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: nil,
        entry: %{
          object: %{
            id: "1",
            type: "Note",
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
            id: "1",
            type: "Note",
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
    assert html =~ ~s(data-role="sensitive-media-hide")
    assert html =~ ~s(id="attachments-post-1")
    assert html =~ ~r/id="attachments-post-1"[^>]*class="[^"]*hidden/
  end

  test "collapses long content behind a show-more toggle" do
    long_content = String.duplicate("a", 600)

    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: nil,
        entry: %{
          object: %{
            id: "1",
            type: "Note",
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
    assert html =~ ~r/id="post-content-post-1"[^>]*class="[^"]*max-h-64/
    assert html =~ ~r/id="post-content-post-1"[^>]*class="[^"]*overflow-hidden/
  end

  test "does not expose unsafe remote ids as share urls" do
    html =
      render_component(&StatusCard.status_card/1, %{
        id: "post-1",
        current_user: %{id: "1"},
        entry: %{
          object: %{
            id: "1",
            type: "Note",
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
