defmodule EgregorosWeb.ProfileLiveTest do
  use EgregorosWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Egregoros.Activities.Note
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Relationships
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

  test "profile shows follow requests for remote accounts until accepted", %{conn: conn, viewer: viewer} do
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

    assert Relationships.get_by_type_actor_object("FollowRequest", viewer.ap_id, remote.ap_id) == nil
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

    assert Relationships.get_by_type_actor_object("FollowRequest", viewer.ap_id, remote.ap_id) == nil
    assert has_element?(view, "button[data-role='profile-follow']")
  end

  test "profile supports muting and unmuting", %{conn: conn, viewer: viewer, profile_user: profile_user} do
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
    assert Relationships.get_by_type_actor_object("Follow", viewer.ap_id, profile_user.ap_id) == nil
    assert Relationships.get_by_type_actor_object("Follow", profile_user.ap_id, viewer.ap_id) == nil
    assert has_element?(view, "button[data-role='profile-unblock']")
    refute has_element?(view, "button[data-role='profile-follow']")

    view
    |> element("button[data-role='profile-unblock']")
    |> render_click()

    assert Relationships.get_by_type_actor_object("Block", viewer.ap_id, profile_user.ap_id) == nil
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
