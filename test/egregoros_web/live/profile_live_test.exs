defmodule EgregorosWeb.ProfileLiveTest do
  use EgregorosWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Egregoros.Activities.Announce
  alias Egregoros.Activities.Note
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Relationships
  alias Egregoros.TestSupport.Fixtures
  alias Egregoros.Users

  setup do
    {:ok, viewer} = Users.create_local_user("alice")
    {:ok, profile_user} = Users.create_local_user("bob")

    %{viewer: viewer, profile_user: profile_user}
  end

  test "profile supports follow and unfollow", %{
    conn: conn,
    viewer: viewer,
    profile_user: profile_user
  } do
    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{profile_user.nickname}")

    refute Relationships.get_by_type_actor_object("Follow", viewer.ap_id, profile_user.ap_id)

    view
    |> element("button[data-role='profile-follow']")
    |> render_click()

    assert %{} =
             relationship =
             Relationships.get_by_type_actor_object("Follow", viewer.ap_id, profile_user.ap_id)

    assert has_element?(view, "button[data-role='profile-unfollow']")

    view
    |> element("button[data-role='profile-unfollow']")
    |> render_click()

    assert Relationships.get(relationship.id) == nil
    assert has_element?(view, "button[data-role='profile-follow']")
  end

  test "profile lists announces by the profile actor", %{
    conn: conn,
    viewer: viewer,
    profile_user: profile_user
  } do
    {:ok, charlie} = Users.create_local_user("charlie")
    assert {:ok, note} = Pipeline.ingest(Note.build(charlie, "Boosted profile note"), local: true)
    assert {:ok, announce} = Pipeline.ingest(Announce.build(profile_user, note), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{profile_user.nickname}")

    assert has_element?(view, "#post-#{announce.id}")
    assert has_element?(view, "#post-#{announce.id}", "Boosted profile note")

    assert has_element?(
             view,
             "#post-#{announce.id} [data-role='reposted-by']",
             profile_user.nickname
           )

    assert has_element?(view, "#post-#{announce.id} [data-role='reposted-by']", "reposted")
    assert has_element?(view, "#post-#{announce.id} [data-role='post-actor-handle']", "@charlie")
  end

  test "profile shows follow requests for remote accounts until accepted", %{
    conn: conn,
    viewer: viewer
  } do
    {:ok, remote} =
      Users.create_user(%{
        nickname: "bob",
        ap_id: "https://remote.example/users/bob",
        inbox: "https://remote.example/users/bob/inbox",
        outbox: "https://remote.example/users/bob/outbox",
        public_key: "remote-key",
        private_key: nil,
        local: false
      })

    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{remote.nickname}@remote.example")

    assert Relationships.get_by_type_actor_object("FollowRequest", viewer.ap_id, remote.ap_id) ==
             nil

    assert has_element?(view, "button[data-role='profile-follow']")

    view
    |> element("button[data-role='profile-follow']")
    |> render_click()

    assert Relationships.get_by_type_actor_object("Follow", viewer.ap_id, remote.ap_id) == nil
    assert Relationships.get_by_type_actor_object("FollowRequest", viewer.ap_id, remote.ap_id)
    assert has_element?(view, "button[data-role='profile-unfollow-request']")

    view
    |> element("button[data-role='profile-unfollow-request']")
    |> render_click()

    assert Relationships.get_by_type_actor_object("FollowRequest", viewer.ap_id, remote.ap_id) ==
             nil

    assert has_element?(view, "button[data-role='profile-follow']")
  end

  test "profile follow requests flip to follows when an accept arrives", %{
    conn: conn,
    viewer: viewer
  } do
    {:ok, remote} =
      Users.create_user(%{
        nickname: "bob",
        ap_id: "https://remote.example/users/bob",
        inbox: "https://remote.example/users/bob/inbox",
        outbox: "https://remote.example/users/bob/outbox",
        public_key: "remote-key",
        private_key: nil,
        local: false
      })

    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{remote.nickname}@remote.example")

    view
    |> element("button[data-role='profile-follow']")
    |> render_click()

    assert %{} =
             follow_request =
             Relationships.get_by_type_actor_object("FollowRequest", viewer.ap_id, remote.ap_id)

    assert has_element?(view, "button[data-role='profile-unfollow-request']")

    assert {:ok, _} =
             Pipeline.ingest(
               %{
                 "id" => "https://remote.example/activities/accept/1",
                 "type" => "Accept",
                 "actor" => remote.ap_id,
                 "object" => %{
                   "id" => follow_request.activity_ap_id,
                   "type" => "Follow",
                   "actor" => viewer.ap_id,
                   "object" => remote.ap_id
                 }
               },
               local: false,
               inbox_user_ap_id: viewer.ap_id
             )

    assert has_element?(view, "button[data-role='profile-unfollow']")
    refute has_element?(view, "button[data-role='profile-unfollow-request']")
  end

  test "profile shows follows-you badge when profile user follows the viewer", %{
    conn: conn,
    viewer: viewer,
    profile_user: profile_user
  } do
    {:ok, _} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/activities/follow/back",
          "type" => "Follow",
          "actor" => profile_user.ap_id,
          "object" => viewer.ap_id
        },
        local: true
      )

    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{profile_user.nickname}")

    assert has_element?(view, "[data-role='profile-follows-you']", "Follows you")
  end

  test "profile shows mutual badge when both accounts follow each other", %{
    conn: conn,
    viewer: viewer,
    profile_user: profile_user
  } do
    {:ok, _} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/activities/follow/back",
          "type" => "Follow",
          "actor" => profile_user.ap_id,
          "object" => viewer.ap_id
        },
        local: true
      )

    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{profile_user.nickname}")

    view
    |> element("button[data-role='profile-follow']")
    |> render_click()

    assert has_element?(view, "[data-role='profile-mutual']", "Mutual")
    refute has_element?(view, "[data-role='profile-follows-you']")
  end

  test "profile supports muting and unmuting", %{
    conn: conn,
    viewer: viewer,
    profile_user: profile_user
  } do
    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{profile_user.nickname}")

    assert Relationships.get_by_type_actor_object("Mute", viewer.ap_id, profile_user.ap_id) == nil

    view
    |> element("button[data-role='profile-mute']")
    |> render_click()

    assert Relationships.get_by_type_actor_object("Mute", viewer.ap_id, profile_user.ap_id)
    assert has_element?(view, "button[data-role='profile-unmute']")

    view
    |> element("button[data-role='profile-unmute']")
    |> render_click()

    assert Relationships.get_by_type_actor_object("Mute", viewer.ap_id, profile_user.ap_id) == nil
    assert has_element?(view, "button[data-role='profile-mute']")
  end

  test "profile supports blocking and unblocking", %{
    conn: conn,
    viewer: viewer,
    profile_user: profile_user
  } do
    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{profile_user.nickname}")

    view
    |> element("button[data-role='profile-follow']")
    |> render_click()

    assert Relationships.get_by_type_actor_object("Follow", viewer.ap_id, profile_user.ap_id)

    {:ok, _} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/activities/follow/back",
          "type" => "Follow",
          "actor" => profile_user.ap_id,
          "object" => viewer.ap_id
        },
        local: true
      )

    assert Relationships.get_by_type_actor_object("Follow", profile_user.ap_id, viewer.ap_id)

    view
    |> element("button[data-role='profile-block']")
    |> render_click()

    assert Relationships.get_by_type_actor_object("Block", viewer.ap_id, profile_user.ap_id)

    assert Relationships.get_by_type_actor_object("Follow", viewer.ap_id, profile_user.ap_id) ==
             nil

    assert Relationships.get_by_type_actor_object("Follow", profile_user.ap_id, viewer.ap_id) ==
             nil

    assert has_element?(view, "button[data-role='profile-unblock']")
    refute has_element?(view, "button[data-role='profile-follow']")

    view
    |> element("button[data-role='profile-unblock']")
    |> render_click()

    assert Relationships.get_by_type_actor_object("Block", viewer.ap_id, profile_user.ap_id) ==
             nil

    assert has_element?(view, "button[data-role='profile-block']")
    assert has_element?(view, "button[data-role='profile-follow']")
  end

  test "profile can load more posts", %{conn: conn, viewer: viewer, profile_user: profile_user} do
    for idx <- 1..25 do
      assert {:ok, _} = Pipeline.ingest(Note.build(profile_user, "Post #{idx}"), local: true)
    end

    notes = Objects.list_notes_by_actor(profile_user.ap_id, limit: 25)
    oldest = List.last(notes)

    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{profile_user.nickname}")

    refute has_element?(view, "#post-#{oldest.id}")

    view
    |> element("button[data-role='profile-load-more']")
    |> render_click()

    assert has_element?(view, "#post-#{oldest.id}")
  end

  test "profile includes loading skeleton placeholders when more posts may load", %{
    conn: conn,
    viewer: viewer,
    profile_user: profile_user
  } do
    Enum.each(1..21, fn idx ->
      assert {:ok, _} = Pipeline.ingest(Note.build(profile_user, "Post #{idx}"), local: true)
    end)

    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{profile_user.nickname}")

    assert has_element?(view, "[data-role='profile-loading-more']")

    assert has_element?(
             view,
             "[data-role='profile-loading-more'] [data-role='skeleton-status-card']"
           )
  end

  test "signed-out users do not see direct messages on profile pages", %{
    conn: conn,
    profile_user: profile_user
  } do
    dm =
      profile_user
      |> Note.build("Secret DM")
      |> Map.put("to", [])
      |> Map.put("cc", [])

    assert {:ok, _} = Pipeline.ingest(dm, local: true)

    assert {:ok, view, _html} = live(conn, "/@#{profile_user.nickname}")

    refute has_element?(view, "article", "Secret DM")
  end

  test "profile stats link to followers and following pages", %{
    conn: conn,
    viewer: viewer,
    profile_user: profile_user
  } do
    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{profile_user.nickname}")

    assert has_element?(view, "a[href='/@#{profile_user.nickname}/followers']")
    assert has_element?(view, "a[href='/@#{profile_user.nickname}/following']")
  end

  test "profile header exposes banner, avatar, and identity elements", %{
    conn: conn,
    viewer: viewer,
    profile_user: profile_user
  } do
    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{profile_user.nickname}")

    assert has_element?(view, "[data-role='profile-banner']")
    assert has_element?(view, "[data-role='profile-avatar']")
    assert has_element?(view, "[data-role='profile-name']", profile_user.nickname)
    assert has_element?(view, "[data-role='profile-handle']", "@#{profile_user.nickname}")
  end

  test "profile banner renders header image when present", %{
    conn: conn,
    viewer: viewer,
    profile_user: profile_user
  } do
    {:ok, profile_user} =
      Users.update_profile(
        profile_user,
        %{
          banner_url: "/uploads/banners/#{profile_user.id}/banner.png"
        }
      )

    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{profile_user.nickname}")

    assert has_element?(view, "[data-role='profile-banner'] img[src*='/uploads/banners/']")
  end

  test "profile avatar resolves remote relative urls against the actor host", %{
    conn: conn,
    viewer: viewer
  } do
    {:ok, remote} =
      Users.create_user(%{
        nickname: "bob",
        ap_id: "https://remote.example/users/bob",
        inbox: "https://remote.example/users/bob/inbox",
        outbox: "https://remote.example/users/bob/outbox",
        public_key: "remote-key",
        private_key: nil,
        local: false,
        avatar_url: "/media/avatar.png"
      })

    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{remote.nickname}@remote.example")

    assert has_element?(
             view,
             "[data-role='profile-avatar'] img[src='https://remote.example/media/avatar.png']"
           )
  end

  test "profile refreshes remote follower counts via ActivityPub", %{conn: conn, viewer: viewer} do
    {:ok, remote} =
      Users.create_user(%{
        nickname: "bob",
        ap_id: "https://remote.example/users/bob",
        inbox: "https://remote.example/users/bob/inbox",
        outbox: "https://remote.example/users/bob/outbox",
        public_key: "remote-key",
        private_key: nil,
        local: false
      })

    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{remote.nickname}@remote.example")

    assert has_element?(view, "a[href='/@#{remote.nickname}@remote.example/followers']", "0")
    assert has_element?(view, "a[href='/@#{remote.nickname}@remote.example/following']", "0")

    expect(Egregoros.HTTP.Mock, :get, fn "https://remote.example/users/bob", _headers ->
      {:ok,
       %{
         status: 200,
         headers: [],
         body: %{
           "@context" => "https://www.w3.org/ns/activitystreams",
           "id" => "https://remote.example/users/bob",
           "type" => "Person",
           "preferredUsername" => "bob",
           "inbox" => "https://remote.example/users/bob/inbox",
           "outbox" => "https://remote.example/users/bob/outbox",
           "publicKey" => %{"publicKeyPem" => "remote-key"},
           "followers" => "https://remote.example/users/bob/followers",
           "following" => "https://remote.example/users/bob/following"
         }
       }}
    end)

    expect(Egregoros.HTTP.Mock, :get, fn "https://remote.example/users/bob/followers", _headers ->
      {:ok,
       %{status: 200, headers: [], body: %{"type" => "OrderedCollection", "totalItems" => 123}}}
    end)

    expect(Egregoros.HTTP.Mock, :get, fn "https://remote.example/users/bob/following", _headers ->
      {:ok,
       %{status: 200, headers: [], body: %{"type" => "OrderedCollection", "totalItems" => 45}}}
    end)

    assert :ok =
             perform_job(Egregoros.Workers.RefreshRemoteUserCounts, %{
               "ap_id" => remote.ap_id
             })

    assert has_element?(view, "a[href='/@#{remote.nickname}@remote.example/followers']", "123")
    assert has_element?(view, "a[href='/@#{remote.nickname}@remote.example/following']", "45")
  end

  test "profile renders remote bios as sanitized html", %{conn: conn, viewer: viewer} do
    {:ok, remote} =
      Users.create_user(%{
        nickname: "lebronjames",
        ap_id: "https://remote.example/users/lebronjames",
        inbox: "https://remote.example/users/lebronjames/inbox",
        outbox: "https://remote.example/users/lebronjames/outbox",
        public_key: "remote-key",
        private_key: nil,
        local: false,
        bio: "<p>the <strong>king</strong></p><script>alert(1)</script>"
      })

    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{remote.nickname}@remote.example")

    assert has_element?(view, "[data-role='profile-bio'] strong", "king")
    refute has_element?(view, "[data-role='profile-bio'] script")
  end

  test "profile renders custom emojis in remote display names", %{conn: conn, viewer: viewer} do
    {:ok, remote} =
      Users.create_user(%{
        nickname: "xaetacore",
        ap_id: "https://neondystopia.world/users/xaetacore",
        inbox: "https://neondystopia.world/users/xaetacore/inbox",
        outbox: "https://neondystopia.world/users/xaetacore/outbox",
        public_key: "remote-key",
        private_key: nil,
        local: false,
        name: ":linux: XaetaCore :420:",
        emojis: [
          %{"shortcode" => "linux", "url" => "https://neondystopia.world/emoji/linux.png"},
          %{"shortcode" => "420", "url" => "https://neondystopia.world/emoji/420.png"}
        ]
      })

    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{remote.nickname}@neondystopia.world")

    assert has_element?(view, "[data-role='profile-name']", "XaetaCore")
    assert has_element?(view, "[data-role='profile-name'] img.emoji[alt=':linux:']")
    assert has_element?(view, "[data-role='profile-name'] img.emoji[alt=':420:']")
  end

  test "profile posts support copying permalinks", %{
    conn: conn,
    viewer: viewer,
    profile_user: profile_user
  } do
    assert {:ok, note} = Pipeline.ingest(Note.build(profile_user, "Copy this"), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{profile_user.nickname}")

    view
    |> element("#post-#{note.id} button[data-role='copy-link']")
    |> render_click()

    assert render(view) =~ "Copied link to clipboard."
  end

  test "profile reply modal can be opened and replies can be posted", %{
    conn: conn,
    viewer: viewer
  } do
    assert {:ok, parent} = Pipeline.ingest(Note.build(viewer, "Parent post"), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{viewer.nickname}")

    assert has_element?(view, "#reply-modal[data-role='reply-modal'][data-state='closed']")
    assert has_element?(view, "#post-#{parent.id} button[data-role='reply']")

    reply_html =
      view
      |> element("#post-#{parent.id} button[data-role='reply']")
      |> render()

    view
    |> form("#reply-modal-form", reply: %{in_reply_to: parent.ap_id, content: "A reply"})
    |> render_submit()

    assert reply_html =~ "egregoros:reply-open"
    assert reply_html =~ parent.ap_id
    refute reply_html =~ "open_reply_modal"

    assert render(view) =~ "Reply posted."

    [reply] = Objects.list_replies_to(parent.ap_id, limit: 1)
    assert reply.data["inReplyTo"] == parent.ap_id
  end

  test "profile reply modal close button dispatches client-side close events", %{
    conn: conn,
    viewer: viewer
  } do
    assert {:ok, parent} = Pipeline.ingest(Note.build(viewer, "Parent post"), local: true)
    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{viewer.nickname}")

    reply_html =
      view
      |> element("#post-#{parent.id} button[data-role='reply']")
      |> render()

    assert reply_html =~ "egregoros:reply-open"
    refute reply_html =~ "open_reply_modal"

    close_html =
      view
      |> element("#reply-modal button[data-role='reply-modal-close']")
      |> render()

    assert close_html =~ "egregoros:reply-close"
    refute close_html =~ "close_reply_modal"
  end

  test "profile reply composer supports content warning toggles", %{conn: conn, viewer: viewer} do
    assert {:ok, _parent} = Pipeline.ingest(Note.build(viewer, "Parent post"), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{viewer.nickname}")

    assert has_element?(view, "#reply-modal [data-role='compose-cw'][data-state='closed']")

    _html =
      render_change(view, "reply_change", %{
        "reply" => %{"ui_cw_open" => "true"}
      })

    assert has_element?(view, "#reply-modal [data-role='compose-cw'][data-state='open']")
  end

  test "profile reply composer keeps client-side option state in sync via reply_change", %{
    conn: conn,
    viewer: viewer
  } do
    assert {:ok, _parent} = Pipeline.ingest(Note.build(viewer, "Parent post"), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{viewer.nickname}")

    render_hook(view, "reply_change", %{
      "reply" => %{"content" => "hello", "spoiler_text" => "CW", "ui_options_open" => "true"}
    })

    assert has_element?(view, "#reply-modal [data-role='compose-cw'][data-state='open']")
    assert has_element?(view, "#reply-modal [data-role='compose-options'][data-state='open']")
  end

  test "profile reply composer supports media uploads and removals", %{
    conn: conn,
    viewer: viewer,
    profile_user: profile_user
  } do
    assert {:ok, _parent} = Pipeline.ingest(Note.build(profile_user, "Parent post"), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{profile_user.nickname}")

    fixture_path = Fixtures.path!("DSCN0010.png")
    content = File.read!(fixture_path)

    upload =
      file_input(view, "#reply-modal-form", :reply_media, [
        %{
          last_modified: 1_694_171_879_000,
          name: "photo.png",
          content: content,
          size: byte_size(content),
          type: "image/png"
        }
      ])

    assert render_upload(upload, "photo.png") =~ "100%"
    assert has_element?(view, "#reply-modal [data-role='media-entry']")

    view
    |> element("#reply-modal button[aria-label='Remove attachment']")
    |> render_click()

    refute has_element?(view, "#reply-modal [data-role='media-entry']")
  end

  test "profile reply composer posts replies with media attachments", %{
    conn: conn,
    viewer: viewer,
    profile_user: profile_user
  } do
    assert {:ok, parent} = Pipeline.ingest(Note.build(profile_user, "Parent post"), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{profile_user.nickname}")

    fixture_path = Fixtures.path!("DSCN0010.png")
    content = File.read!(fixture_path)

    upload =
      file_input(view, "#reply-modal-form", :reply_media, [
        %{
          last_modified: 1_694_171_879_000,
          name: "photo.png",
          content: content,
          size: byte_size(content),
          type: "image/png"
        }
      ])

    expect(Egregoros.MediaStorage.Mock, :store_media, fn passed_user, passed_upload ->
      assert passed_user.id == viewer.id
      assert passed_upload.filename == "photo.png"
      assert passed_upload.content_type == "image/png"
      {:ok, "/uploads/media/#{passed_user.id}/photo.png"}
    end)

    assert render_upload(upload, "photo.png") =~ "100%"

    view
    |> form("#reply-modal-form", reply: %{content: "Reply with media", in_reply_to: parent.ap_id})
    |> render_submit()

    assert render(view) =~ "Reply posted."

    [reply] = Objects.list_replies_to(parent.ap_id, limit: 1)
    assert List.wrap(reply.data["attachment"]) != []
  end

  test "profile reply composer surfaces upload errors when attachments cannot be stored", %{
    conn: conn,
    viewer: viewer,
    profile_user: profile_user
  } do
    assert {:ok, parent} = Pipeline.ingest(Note.build(profile_user, "Parent post"), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{profile_user.nickname}")

    upload =
      file_input(view, "#reply-modal-form", :reply_media, [
        %{
          last_modified: 1_694_171_879_000,
          name: "photo.png",
          content: "png",
          size: 3,
          type: "image/png"
        }
      ])

    expect(Egregoros.MediaStorage.Mock, :store_media, fn _user, _upload ->
      {:error, :storage_failed}
    end)

    assert render_upload(upload, "photo.png") =~ "100%"

    view
    |> form("#reply-modal-form", reply: %{content: "Reply with media", in_reply_to: parent.ap_id})
    |> render_submit()

    assert render(view) =~ "Could not upload attachment."
    assert Objects.list_replies_to(parent.ap_id, limit: 10) == []
  end

  test "profile reply composer validates content length and emptiness", %{
    conn: conn,
    viewer: viewer
  } do
    assert {:ok, parent} = Pipeline.ingest(Note.build(viewer, "Parent post"), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{viewer.nickname}")

    too_long = String.duplicate("a", 5001)

    view
    |> form("#reply-modal-form", reply: %{in_reply_to: parent.ap_id, content: too_long})
    |> render_submit()

    assert render(view) =~ "Reply is too long."
    assert Objects.list_replies_to(parent.ap_id, limit: 10) == []

    view
    |> form("#reply-modal-form", reply: %{in_reply_to: parent.ap_id, content: "   \n"})
    |> render_submit()

    assert render(view) =~ "Reply can&#39;t be empty."
    assert Objects.list_replies_to(parent.ap_id, limit: 10) == []
  end

  test "profile reply composer mention autocomplete suggests users", %{
    conn: conn,
    viewer: viewer
  } do
    assert {:ok, _parent} = Pipeline.ingest(Note.build(viewer, "Parent post"), local: true)
    {:ok, _} = Users.create_local_user("bob2")

    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{viewer.nickname}")

    _html = render_hook(view, "mention_search", %{"q" => "bo", "scope" => "reply-modal"})
    assert has_element?(view, "[data-role='mention-suggestion']", "@bob2")

    _html = render_hook(view, "mention_clear", %{"scope" => "reply-modal"})
    refute has_element?(view, "[data-role='mention-suggestion']")
  end

  test "profile supports liking, reposting, reacting, and bookmarking posts", %{
    conn: conn,
    viewer: viewer,
    profile_user: profile_user
  } do
    assert {:ok, note} =
             Pipeline.ingest(Note.build(profile_user, "Interact with me"), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{profile_user.nickname}")

    view
    |> element("#post-#{note.id} button[data-role='like']")
    |> render_click()

    assert Objects.get_by_type_actor_object("Like", viewer.ap_id, note.ap_id)

    view
    |> element("#post-#{note.id} button[data-role='repost']")
    |> render_click()

    assert Objects.get_by_type_actor_object("Announce", viewer.ap_id, note.ap_id)

    view
    |> element("#post-#{note.id} button[data-role='reaction'][data-emoji='🔥']")
    |> render_click()

    assert Objects.get_emoji_react(viewer.ap_id, note.ap_id, "🔥")

    view
    |> element("#post-#{note.id} button[data-role='bookmark']")
    |> render_click()

    assert Relationships.get_by_type_actor_object("Bookmark", viewer.ap_id, note.ap_id)
  end

  test "profile posts provide media viewer controls without a server roundtrip", %{
    conn: conn,
    viewer: viewer,
    profile_user: profile_user
  } do
    note =
      Note.build(profile_user, "With images")
      |> Map.put("attachment", [
        %{
          "mediaType" => "image/png",
          "name" => "first",
          "url" => [%{"href" => "/uploads/first.png", "mediaType" => "image/png"}]
        },
        %{
          "mediaType" => "image/png",
          "name" => "second",
          "url" => [%{"href" => "/uploads/second.png", "mediaType" => "image/png"}]
        }
      ])

    assert {:ok, object} = Pipeline.ingest(note, local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{profile_user.nickname}")

    assert has_element?(view, "#media-viewer[data-role='media-viewer'][data-state='closed']")

    html =
      view
      |> element("#post-#{object.id} button[data-role='attachment-open'][data-index='0']")
      |> render()

    assert html =~ "egregoros:media-open"
    refute html =~ "open_media"

    prev_html =
      view
      |> element("#media-viewer [data-role='media-viewer-prev']")
      |> render()

    next_html =
      view
      |> element("#media-viewer [data-role='media-viewer-next']")
      |> render()

    assert prev_html =~ "egregoros:media-prev"
    refute prev_html =~ "media_prev"
    assert next_html =~ "egregoros:media-next"
    refute next_html =~ "media_next"

    close_html =
      view
      |> element("#media-viewer [data-role='media-viewer-close']")
      |> render()

    assert close_html =~ "egregoros:media-close"
    refute close_html =~ "close_media"
  end

  test "profile allows deleting your own posts", %{conn: conn, viewer: viewer} do
    assert {:ok, note} = Pipeline.ingest(Note.build(viewer, "Delete me"), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{viewer.nickname}")

    assert has_element?(view, "#post-#{note.id} [data-role='delete-post']")

    view
    |> element("#post-#{note.id} button[data-role='delete-post-confirm']")
    |> render_click()

    assert Objects.get(note.id) == nil
    refute has_element?(view, "#post-#{note.id}")
  end

  test "remote profiles are addressed by nickname@domain and do not hijack local routes", %{
    conn: conn,
    viewer: viewer
  } do
    {:ok, _remote} =
      Users.create_user(%{
        nickname: "lain",
        domain: "lain.com",
        ap_id: "https://lain.com/users/lain",
        inbox: "https://lain.com/users/lain/inbox",
        outbox: "https://lain.com/users/lain/outbox",
        public_key: "remote-key",
        private_key: nil,
        local: false
      })

    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})

    {:ok, view, _html} = live(conn, "/@lain@lain.com")
    assert has_element?(view, "[data-role='profile-header']", "@lain@lain.com")

    {:ok, view, _html} = live(conn, "/@lain")
    assert has_element?(view, "section", "Profile not found.")
  end

  test "profile includes a badges link", %{conn: conn, viewer: viewer} do
    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{viewer.nickname}")

    assert has_element?(
             view,
             "[data-role='profile-badges-link'][href='/@#{viewer.nickname}/badges']"
           )
  end

  test "multiple remote users can share a nickname across domains", %{viewer: _viewer} do
    {:ok, _remote_a} =
      Users.create_user(%{
        nickname: "lain",
        domain: "lain.com",
        ap_id: "https://lain.com/users/lain",
        inbox: "https://lain.com/users/lain/inbox",
        outbox: "https://lain.com/users/lain/outbox",
        public_key: "remote-key-a",
        private_key: nil,
        local: false
      })

    assert {:ok, _remote_b} =
             Users.create_user(%{
               nickname: "lain",
               domain: "example.com",
               ap_id: "https://example.com/users/lain",
               inbox: "https://example.com/users/lain/inbox",
               outbox: "https://example.com/users/lain/outbox",
               public_key: "remote-key-b",
               private_key: nil,
               local: false
             })
  end
end
