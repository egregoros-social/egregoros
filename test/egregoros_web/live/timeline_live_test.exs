defmodule EgregorosWeb.TimelineLiveTest do
  use EgregorosWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Egregoros.Activities.Note
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Publish
  alias Egregoros.Relationships
  alias Egregoros.TestSupport.Fixtures
  alias Egregoros.Timeline
  alias Egregoros.Users

  setup do
    Timeline.reset()

    {:ok, user} = Users.create_local_user("alice")
    %{user: user}
  end

  test "posting updates the timeline without refresh", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    refute has_element?(view, "article", "Hello world")

    view
    |> form("#timeline-form", post: %{content: "Hello world"})
    |> render_submit()

    assert has_element?(view, "article", "Hello world")
  end

  test "timeline escapes unsafe html when posting locally", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    view
    |> form("#timeline-form", post: %{content: "<script>alert(1)</script>"})
    |> render_submit()

    html = render(view)

    refute html =~ "<script"
    assert html =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
  end

  test "timeline renders sidebar and feed panels", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#timeline-shell")
    assert has_element?(view, "#timeline-sidebar")
    assert has_element?(view, "#timeline-feed")
    assert has_element?(view, "#timeline-sidebar #compose-panel")
    refute has_element?(view, "#timeline-aside")
  end

  test "public timeline does not include direct messages", %{conn: conn, user: user} do
    {:ok, _} = Publish.post_note(user, "Hello public")
    {:ok, _} = Publish.post_note(user, "Secret DM", visibility: "direct")

    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "article", "Hello public")
    refute has_element?(view, "article", "Secret DM")
  end

  test "home timeline includes direct messages addressed to the signed-in user", %{
    conn: conn,
    user: user
  } do
    {:ok, bob} = Users.create_local_user("bob")
    {:ok, _} = Publish.post_note(user, "@bob Secret DM", visibility: "direct")

    conn = Plug.Test.init_test_session(conn, %{user_id: bob.id})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "article", "Secret DM")
  end

  test "refresh helpers do not leak DMs via arbitrary toggle events", %{conn: conn, user: user} do
    {:ok, bob} = Users.create_local_user("bob")
    {:ok, _charlie} = Users.create_local_user("charlie")

    {:ok, create} =
      Publish.post_note(bob, "@charlie really-secret-lv-leak-check", visibility: "direct")

    dm_note = Objects.get_by_ap_id(create.object)
    assert dm_note

    {:ok, public_create} = Publish.post_note(bob, "A public post", visibility: "public")
    public_note = Objects.get_by_ap_id(public_create.object)
    assert public_note

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#compose-open-button")
    refute has_element?(view, "#post-#{dm_note.id}")
    refute has_element?(view, "#post-#{public_note.id}")

    _html = render_click(view, "toggle_like", %{"id" => public_note.id})
    assert has_element?(view, "#post-#{public_note.id}")

    _html = render_click(view, "toggle_like", %{"id" => dm_note.id})
    refute has_element?(view, "#post-#{dm_note.id}")
  end

  test "theme toggle buttons are labeled for accessibility", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "button[data-phx-theme='system'][aria-label='Use system theme']")
    assert has_element?(view, "button[data-phx-theme='light'][aria-label='Use light theme']")
    assert has_element?(view, "button[data-phx-theme='dark'][aria-label='Use dark theme']")
  end

  test "follow panels are removed from the timeline UI", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#compose-panel")
    refute has_element?(view, "#follow-panel")
    refute has_element?(view, "#following-panel")
  end

  test "compose character counter updates after compose_change", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#timeline-form[phx-hook='ComposeSettings']")

    assert has_element?(
             view,
             "textarea[data-role='compose-content'][phx-hook='ComposeCharCounter'][data-max-chars='5000']"
           )

    assert has_element?(view, "[data-role='compose-char-counter']", "5000")

    view
    |> form("#timeline-form", post: %{content: "hello"})
    |> render_change()

    assert has_element?(view, "[data-role='compose-char-counter']", "4995")
  end

  test "compose mention autocomplete suggests users and can be cleared", %{conn: conn, user: user} do
    {:ok, _} = Users.create_local_user("bob")

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    _html = render_hook(view, "mention_search", %{"q" => "bo", "scope" => "compose"})

    assert has_element?(view, "[data-role='mention-suggestion']", "@bob")

    _html = render_hook(view, "mention_clear", %{"scope" => "compose"})
    refute has_element?(view, "[data-role='mention-suggestion']")
  end

  test "reply modal stays open after selecting a target", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    {:ok, create} = Publish.post_note(user, "Hello")
    note = Objects.get_by_ap_id(create.object)
    assert note

    refute has_element?(view, "#reply-modal[data-state='open']")
    assert has_element?(view, "#reply-modal.hidden")

    _html =
      render_hook(view, "open_reply_modal", %{
        "in_reply_to" => note.ap_id,
        "actor_handle" => "@alice"
      })

    assert has_element?(view, "#reply-modal[data-state='open']")
    refute has_element?(view, "#reply-modal.hidden")
  end

  test "timeline renders custom emojis in remote actor display names", %{conn: conn, user: _user} do
    {:ok, remote} =
      Users.create_user(%{
        nickname: "xaetacore",
        ap_id: "https://neondystopia.world/users/xaetacore",
        inbox: "https://neondystopia.world/users/xaetacore/inbox",
        outbox: "https://neondystopia.world/users/xaetacore/outbox",
        public_key: "remote-key",
        private_key: nil,
        local: false,
        name: ":linux: XaetaCore",
        emojis: [
          %{"shortcode" => "linux", "url" => "https://neondystopia.world/emoji/linux.png"}
        ]
      })

    assert {:ok, _} =
             Pipeline.ingest(
               %{
                 "id" => "https://neondystopia.world/objects/1",
                 "type" => "Note",
                 "actor" => remote.ap_id,
                 "content" => "Hello from xaeta",
                 "to" => ["https://www.w3.org/ns/activitystreams#Public"],
                 "cc" => []
               },
               local: false
             )

    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "[data-role='post-actor-name']", "XaetaCore")
    assert has_element?(view, "[data-role='post-actor-name'] img.emoji[alt=':linux:']")
  end

  test "compose options panel can be persisted via ui_options_open param", %{
    conn: conn,
    user: user
  } do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(
             view,
             "input[type='hidden'][data-role='compose-options-state'][name='post[ui_options_open]'][value='false']"
           )

    assert has_element?(view, "#compose-options[data-state='closed']")

    _html = render_change(view, "compose_change", %{"post" => %{"ui_options_open" => "true"}})

    assert has_element?(view, "#compose-options[data-state='open']")
  end

  test "compose uses dedicated visibility and language menus separate from advanced options", %{
    conn: conn,
    user: user
  } do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "button[data-role='compose-visibility-pill']")

    assert has_element?(
             view,
             "[data-role='compose-visibility-menu'] input[name='post[visibility]']"
           )

    assert has_element?(view, "button[data-role='compose-language-pill']")
    assert has_element?(view, "[data-role='compose-language-menu'] input[name='post[language]']")

    refute has_element?(view, "#compose-options select[name='post[visibility]']")
    refute has_element?(view, "#compose-options input[name='post[language]']")
  end

  test "posting rejects content longer than 5000 characters", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    too_long = String.duplicate("a", 5001)

    view
    |> form("#timeline-form", post: %{content: too_long})
    |> render_submit()

    assert has_element?(view, "[data-role='compose-error']", "Post is too long.")
    assert Objects.list_notes() == []
  end

  test "compose submit button disables when over the character limit", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    too_long = String.duplicate("a", 5001)
    _html = render_change(view, "compose_change", %{"post" => %{"content" => too_long}})

    assert has_element?(view, "form#timeline-form button[type='submit'][disabled]")
  end

  test "compose shows an over-limit hint when exceeding max chars", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    too_long = String.duplicate("a", 5001)
    _html = render_change(view, "compose_change", %{"post" => %{"content" => too_long}})

    assert has_element?(view, "[data-role='compose-char-error']", "Too long by 1 character.")
  end

  test "compose submit button disables when empty and enables with content", %{
    conn: conn,
    user: user
  } do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "form#timeline-form button[type='submit'][disabled]")

    _html = render_change(view, "compose_change", %{"post" => %{"content" => "hello"}})

    refute has_element?(view, "form#timeline-form button[type='submit'][disabled]")
  end

  test "compose renders an emoji picker without requiring a server roundtrip", %{
    conn: conn,
    user: user
  } do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "[data-role='compose-emoji-picker']")

    assert has_element?(
             view,
             "[data-role='compose-emoji-option'][data-emoji='😀']"
           )

    refute has_element?(view, "[data-role='compose-emoji'][disabled]")
  end

  test "post cards show actor handle", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    view
    |> form("#timeline-form", post: %{content: "Hello world"})
    |> render_submit()

    [note] = Objects.list_notes()

    assert has_element?(view, "#post-#{note.id} [data-role='post-actor-handle']", "@alice")
  end

  test "logged-in users default to home timeline", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "[data-role='timeline-current']", "home")
  end

  test "timeline can be selected via params", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/?timeline=public")

    assert has_element?(view, "[data-role='timeline-current']", "public")
  end

  test "compose sheet can be opened and closed", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#compose-overlay[data-state='closed']")

    view
    |> element("button[data-role='compose-open']")
    |> render_click()

    assert has_element?(view, "#compose-overlay[data-state='open']")

    view
    |> element("button[data-role='compose-close']")
    |> render_click()

    assert has_element?(view, "#compose-overlay[data-state='closed']")
  end

  test "public timeline sanitizes remote html content", %{conn: conn} do
    assert {:ok, _object} =
             Pipeline.ingest(
               %{
                 "id" => "https://remote.example/objects/unsafe-1",
                 "type" => "Note",
                 "attributedTo" => "https://remote.example/users/bob",
                 "content" => "<p>ok</p><script>alert(1)</script>",
                 "to" => ["https://www.w3.org/ns/activitystreams#Public"],
                 "cc" => ["https://remote.example/users/bob/followers"]
               },
               local: false
             )

    {:ok, view, _html} = live(conn, "/?timeline=public")

    html = render(view)

    assert html =~ "ok"
    refute html =~ "<script"
  end

  test "signed-out users do not see interaction buttons in the public timeline", %{
    conn: conn,
    user: user
  } do
    assert {:ok, _} = Pipeline.ingest(Note.build(user, "Public post"), local: true)
    [note] = Objects.list_notes()

    {:ok, view, _html} = live(conn, "/?timeline=public")

    assert has_element?(view, "#post-#{note.id}")
    refute has_element?(view, "#post-#{note.id} button[data-role='like']")
    refute has_element?(view, "#post-#{note.id} button[data-role='repost']")
    refute has_element?(view, "#post-#{note.id} button[data-role='reaction']")
  end

  test "reply buttons dispatch reply modal events without navigation", %{conn: conn, user: user} do
    assert {:ok, _} = Pipeline.ingest(Note.build(user, "Reply target"), local: true)
    [note] = Objects.list_notes()

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#reply-modal[data-role='reply-modal'][data-state='closed']")
    assert has_element?(view, "#post-#{note.id} button[data-role='reply']")

    html =
      view
      |> element("#post-#{note.id} button[data-role='reply']")
      |> render()

    assert html =~ "egregoros:reply-open"
    refute html =~ "?reply=true"
  end

  test "signed-in users can reply from the timeline", %{conn: conn, user: user} do
    assert {:ok, parent} = Pipeline.ingest(Note.build(user, "Parent post"), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    view
    |> element("#post-#{parent.id} button[data-role='reply']")
    |> render_click()

    view
    |> form("#reply-modal-form", reply: %{content: "A reply"})
    |> render_submit()

    [reply] = Objects.list_replies_to(parent.ap_id, limit: 1)
    assert reply.data["inReplyTo"] == parent.ap_id
  end

  test "timeline can load more posts", %{conn: conn, user: user} do
    for idx <- 1..25 do
      assert {:ok, _} = Pipeline.ingest(Note.build(user, "Post #{idx}"), local: true)
    end

    notes = Objects.list_notes(25)
    oldest = List.last(notes)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    refute has_element?(view, "#post-#{oldest.id}")

    view
    |> element("button[data-role='load-more']")
    |> render_click()

    assert has_element?(view, "#post-#{oldest.id}")
  end

  test "timeline exposes an infinite scroll sentinel for loading more posts", %{
    conn: conn,
    user: user
  } do
    for idx <- 1..25 do
      assert {:ok, _} = Pipeline.ingest(Note.build(user, "Post #{idx}"), local: true)
    end

    notes = Objects.list_notes(25)
    oldest = List.last(notes)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#timeline-bottom-sentinel[phx-hook='TimelineBottomSentinel']")
    refute has_element?(view, "#post-#{oldest.id}")

    render_hook(view, "load_more", %{})

    assert has_element?(view, "#post-#{oldest.id}")
  end

  test "liking a post creates a Like activity", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    view
    |> form("#timeline-form", post: %{content: "Hello world"})
    |> render_submit()

    [note] = Objects.list_notes()

    refute Objects.get_by_type_actor_object("Like", user.ap_id, note.ap_id)

    view
    |> element("#post-#{note.id} button[data-role='like']")
    |> render_click()

    assert Objects.get_by_type_actor_object("Like", user.ap_id, note.ap_id)
    assert has_element?(view, "#post-#{note.id} button[data-role='like']", "Unlike")
  end

  test "reposting a post creates an Announce activity", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    view
    |> form("#timeline-form", post: %{content: "Hello world"})
    |> render_submit()

    [note] = Objects.list_notes()

    refute Objects.get_by_type_actor_object("Announce", user.ap_id, note.ap_id)

    view
    |> element("#post-#{note.id} button[data-role='repost']")
    |> render_click()

    assert Objects.get_by_type_actor_object("Announce", user.ap_id, note.ap_id)
    assert has_element?(view, "#post-#{note.id} button[data-role='repost']", "Unrepost")
  end

  test "reacting to a post creates an EmojiReact activity", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    view
    |> form("#timeline-form", post: %{content: "Hello world"})
    |> render_submit()

    [note] = Objects.list_notes()

    refute Objects.get_emoji_react(user.ap_id, note.ap_id, "🔥")

    view
    |> element("#post-#{note.id} button[data-role='reaction'][data-emoji='🔥']")
    |> render_click()

    assert Objects.get_emoji_react(user.ap_id, note.ap_id, "🔥")

    assert has_element?(
             view,
             "#post-#{note.id} button[data-role='reaction'][data-emoji='🔥']",
             "1"
           )
  end

  test "bookmarking a post toggles a local bookmark", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    view
    |> form("#timeline-form", post: %{content: "Hello world"})
    |> render_submit()

    [note] = Objects.list_notes()

    refute Relationships.get_by_type_actor_object("Bookmark", user.ap_id, note.ap_id)

    view
    |> element("#post-#{note.id} button[data-role='bookmark']")
    |> render_click()

    assert Relationships.get_by_type_actor_object("Bookmark", user.ap_id, note.ap_id)
    assert has_element?(view, "#post-#{note.id} button[data-role='bookmark']", "Unbookmark")

    view
    |> element("#post-#{note.id} button[data-role='bookmark']")
    |> render_click()

    refute Relationships.get_by_type_actor_object("Bookmark", user.ap_id, note.ap_id)
    assert has_element?(view, "#post-#{note.id} button[data-role='bookmark']", "Bookmark")
  end

  test "users can delete their own posts from the timeline", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    view
    |> form("#timeline-form", post: %{content: "Delete me"})
    |> render_submit()

    [note] = Objects.list_notes()

    assert has_element?(view, "#post-#{note.id} [data-role='delete-post']")

    view
    |> element("#post-#{note.id} button[data-role='delete-post-confirm']")
    |> render_click()

    assert Objects.get(note.id) == nil
    refute has_element?(view, "#post-#{note.id}")
  end

  test "delete affordances are hidden for posts not owned by the viewer", %{
    conn: conn,
    user: user
  } do
    {:ok, bob} = Users.create_local_user("bob")
    assert {:ok, note} = Pipeline.ingest(Note.build(bob, "Hello"), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/?timeline=public")

    assert has_element?(view, "#post-#{note.id}")
    refute has_element?(view, "#post-#{note.id} [data-role='delete-post']")
  end

  test "posting with an attachment renders it in the timeline", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    fixture_path = Fixtures.path!("DSCN0010.png")
    content = File.read!(fixture_path)

    upload =
      file_input(view, "#timeline-form", :media, [
        %{
          last_modified: 1_694_171_879_000,
          name: "photo.png",
          content: content,
          size: byte_size(content),
          type: "image/png"
        }
      ])

    expect(Egregoros.MediaStorage.Mock, :store_media, fn passed_user, passed_upload ->
      assert passed_user.id == user.id
      assert passed_upload.filename == "photo.png"
      assert passed_upload.content_type == "image/png"
      {:ok, "/uploads/media/#{passed_user.id}/photo.png"}
    end)

    assert render_upload(upload, "photo.png") =~ "100%"

    view
    |> form("#timeline-form", post: %{content: "Hello with media"})
    |> render_submit()

    [note] = Objects.list_notes()

    assert has_element?(view, "#post-#{note.id} img[data-role='attachment']")
  end

  test "compose Add media button is wired to the hidden file input", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#timeline-form [data-role='compose-editor']")
    assert has_element?(view, "#timeline-form [data-role='compose-toolbar']")

    assert has_element?(
             view,
             "#timeline-form [data-role='compose-add-media'][aria-label='Add media']"
           )

    assert has_element?(view, "#timeline-form [data-role='compose-add-media'] input[type='file']")

    html =
      view
      |> element("#timeline-form [data-role='compose-add-media']")
      |> render()

    assert html =~ "type=\"file\""
    assert html =~ "Phoenix.LiveFileUpload"
  end

  test "posting with a video attachment renders it in the timeline", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    upload =
      file_input(view, "#timeline-form", :media, [
        %{
          last_modified: 1_694_171_879_000,
          name: "clip.mp4",
          content: "video",
          size: 5,
          type: "video/mp4"
        }
      ])

    expect(Egregoros.MediaStorage.Mock, :store_media, fn passed_user, passed_upload ->
      assert passed_user.id == user.id
      assert passed_upload.filename == "clip.mp4"
      assert passed_upload.content_type == "video/mp4"
      {:ok, "/uploads/media/#{passed_user.id}/clip.mp4"}
    end)

    assert render_upload(upload, "clip.mp4") =~ "100%"

    view
    |> form("#timeline-form", post: %{content: "Hello with video"})
    |> render_submit()

    [note] = Objects.list_notes()

    assert has_element?(view, "#post-#{note.id} video[data-role='attachment'][data-kind='video']")
  end

  test "video uploads render previews in the composer", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    upload =
      file_input(view, "#timeline-form", :media, [
        %{
          last_modified: 1_694_171_879_000,
          name: "clip.mp4",
          content: "video",
          size: 5,
          type: "video/mp4"
        }
      ])

    assert render_upload(upload, "clip.mp4") =~ "100%"

    assert has_element?(view, "video[data-role='upload-preview'][data-kind='video']")
    assert has_element?(view, "video[data-role='upload-player'][data-kind='video']")
  end

  test "audio uploads render previews in the composer", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    upload =
      file_input(view, "#timeline-form", :media, [
        %{
          last_modified: 1_694_171_879_000,
          name: "clip.ogg",
          content: "audio",
          size: 5,
          type: "audio/ogg"
        }
      ])

    assert render_upload(upload, "clip.ogg") =~ "100%"

    assert has_element?(view, "audio[data-role='upload-player'][data-kind='audio']")
  end

  test "posting with only an attachment is allowed", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    fixture_path = Fixtures.path!("DSCN0010.png")
    content = File.read!(fixture_path)

    upload =
      file_input(view, "#timeline-form", :media, [
        %{
          last_modified: 1_694_171_879_000,
          name: "photo.png",
          content: content,
          size: byte_size(content),
          type: "image/png"
        }
      ])

    expect(Egregoros.MediaStorage.Mock, :store_media, fn passed_user, passed_upload ->
      assert passed_user.id == user.id
      assert passed_upload.filename == "photo.png"
      assert passed_upload.content_type == "image/png"
      {:ok, "/uploads/media/#{passed_user.id}/photo.png"}
    end)

    assert render_upload(upload, "photo.png") =~ "100%"

    view
    |> form("#timeline-form", post: %{content: ""})
    |> render_submit()

    assert [_note] = Objects.list_notes()
    refute has_element?(view, "[data-role='compose-error']")
  end

  test "invalid attachment uploads are rejected and block posting", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    upload =
      file_input(view, "#timeline-form", :media, [
        %{
          last_modified: 1_694_171_879_000,
          name: "bad.txt",
          content: "bad",
          size: 3,
          type: "text/plain"
        }
      ])

    _ = render_upload(upload, "bad.txt")
    assert has_element?(view, "[data-role='upload-error']")

    view
    |> form("#timeline-form", post: %{content: "Hello world"})
    |> render_submit()

    assert Objects.list_notes() == []
    assert has_element?(view, "[data-role='compose-error']")
  end

  test "oversized attachment uploads are rejected and block posting", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    content = :binary.copy("a", 10_000_001)

    upload =
      file_input(view, "#timeline-form", :media, [
        %{
          last_modified: 1_694_171_879_000,
          name: "huge.png",
          content: content,
          size: byte_size(content),
          type: "image/png"
        }
      ])

    _ = render_upload(upload, "huge.png")
    assert has_element?(view, "[data-role='upload-error']")

    view
    |> form("#timeline-form", post: %{content: "Hello world"})
    |> render_submit()

    assert Objects.list_notes() == []
    assert has_element?(view, "[data-role='compose-error']")
  end

  test "duplicate likes are deduped and can be fully unliked", %{conn: conn, user: user} do
    {:ok, note} = Pipeline.ingest(Note.build(user, "Hello world"), local: true)

    assert {:ok, _} =
             Pipeline.ingest(
               %{
                 "id" => "https://local.example/activities/like/1",
                 "type" => "Like",
                 "actor" => user.ap_id,
                 "object" => note.ap_id
               },
               local: true
             )

    assert {:ok, _} =
             Pipeline.ingest(
               %{
                 "id" => "https://local.example/activities/like/2",
                 "type" => "Like",
                 "actor" => user.ap_id,
                 "object" => note.ap_id
               },
               local: true
             )

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#post-#{note.id} button[data-role='like']", "Unlike")
    assert has_element?(view, "#post-#{note.id} button[data-role='like']", "1")

    view
    |> element("#post-#{note.id} button[data-role='like']")
    |> render_click()

    assert has_element?(view, "#post-#{note.id} button[data-role='like']", "Like")
    assert has_element?(view, "#post-#{note.id} button[data-role='like']", "0")
  end

  test "duplicate reactions are deduped and can be fully unreacted", %{conn: conn, user: user} do
    {:ok, note} = Pipeline.ingest(Note.build(user, "Hello world"), local: true)

    assert {:ok, _} =
             Pipeline.ingest(
               %{
                 "id" => "https://local.example/activities/react/1",
                 "type" => "EmojiReact",
                 "actor" => user.ap_id,
                 "object" => note.ap_id,
                 "content" => "🔥"
               },
               local: true
             )

    assert {:ok, _} =
             Pipeline.ingest(
               %{
                 "id" => "https://local.example/activities/react/2",
                 "type" => "EmojiReact",
                 "actor" => user.ap_id,
                 "object" => note.ap_id,
                 "content" => "🔥"
               },
               local: true
             )

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(
             view,
             "#post-#{note.id} button[data-role='reaction'][data-emoji='🔥']",
             "1"
           )

    view
    |> element("#post-#{note.id} button[data-role='reaction'][data-emoji='🔥']")
    |> render_click()

    assert has_element?(
             view,
             "#post-#{note.id} button[data-role='reaction'][data-emoji='🔥']",
             "0"
           )
  end

  test "timeline buffers new posts when the user is not at the top", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    refute has_element?(view, "button[data-role='new-posts']")

    render_hook(view, "timeline_at_top", %{"at_top" => false})

    assert {:ok, _post} = Pipeline.ingest(Note.build(user, "Buffered post"), local: true)
    _ = :sys.get_state(view.pid)

    refute has_element?(view, "article", "Buffered post")
    assert has_element?(view, "button[data-role='new-posts']")

    render_hook(view, "timeline_at_top", %{"at_top" => true})
    _ = :sys.get_state(view.pid)

    assert has_element?(view, "article", "Buffered post")
    refute has_element?(view, "button[data-role='new-posts']")
  end

  test "attachment open buttons dispatch media viewer events without a server roundtrip", %{
    conn: conn
  } do
    assert {:ok, note} =
             Pipeline.ingest(
               %{
                 "id" => "https://remote.example/objects/with-image",
                 "type" => "Note",
                 "attributedTo" => "https://remote.example/users/bob",
                 "content" => "<p>Hello</p>",
                 "to" => ["https://www.w3.org/ns/activitystreams#Public"],
                 "cc" => ["https://remote.example/users/bob/followers"],
                 "attachment" => [
                   %{
                     "type" => "Document",
                     "mediaType" => "image/png",
                     "name" => "Alt",
                     "url" => "https://cdn.example/image.png"
                   }
                 ]
               },
               local: false
             )

    {:ok, view, _html} = live(conn, "/?timeline=public")

    assert has_element?(view, "#media-viewer[data-role='media-viewer'][data-state='closed']")

    html =
      view
      |> element("#post-#{note.id} button[data-role='attachment-open'][data-index='0']")
      |> render()

    assert html =~ "egregoros:media-open"
    refute html =~ "open_media"
    refute html =~ "phx-value-id="
    refute html =~ "phx-value-index="

    close_html =
      view
      |> element("#media-viewer button[data-role='media-viewer-close']")
      |> render()

    assert close_html =~ "egregoros:media-close"
    refute close_html =~ "close_media"
  end

  test "video attachments render a preview and a media viewer affordance", %{conn: conn} do
    assert {:ok, note} =
             Pipeline.ingest(
               %{
                 "id" => "https://remote.example/objects/with-video-viewer",
                 "type" => "Note",
                 "attributedTo" => "https://remote.example/users/bob",
                 "content" => "<p>Hello</p>",
                 "to" => ["https://www.w3.org/ns/activitystreams#Public"],
                 "cc" => ["https://remote.example/users/bob/followers"],
                 "attachment" => [
                   %{
                     "type" => "Document",
                     "mediaType" => "video/mp4",
                     "name" => "Clip",
                     "url" => "https://cdn.example/clip.mp4"
                   }
                 ]
               },
               local: false
             )

    {:ok, view, _html} = live(conn, "/?timeline=public")

    assert has_element?(view, "#media-viewer[data-role='media-viewer'][data-state='closed']")

    assert has_element?(
             view,
             "#post-#{note.id} video[data-role='attachment'][data-kind='video']"
           )

    html =
      view
      |> element("#post-#{note.id} button[data-role='attachment-open'][data-index='0']")
      |> render()

    assert html =~ "egregoros:media-open"
    refute html =~ "open_media"
  end

  test "audio attachments render a player and a media viewer affordance", %{conn: conn} do
    assert {:ok, note} =
             Pipeline.ingest(
               %{
                 "id" => "https://remote.example/objects/with-audio-viewer",
                 "type" => "Note",
                 "attributedTo" => "https://remote.example/users/bob",
                 "content" => "<p>Hello</p>",
                 "to" => ["https://www.w3.org/ns/activitystreams#Public"],
                 "cc" => ["https://remote.example/users/bob/followers"],
                 "attachment" => [
                   %{
                     "type" => "Document",
                     "mediaType" => "audio/ogg",
                     "name" => "Audio",
                     "url" => "https://cdn.example/clip.ogg"
                   }
                 ]
               },
               local: false
             )

    {:ok, view, _html} = live(conn, "/?timeline=public")

    assert has_element?(view, "#media-viewer[data-role='media-viewer'][data-state='closed']")

    assert has_element?(
             view,
             "#post-#{note.id} audio[data-role='attachment'][data-kind='audio']"
           )

    html =
      view
      |> element("#post-#{note.id} button[data-role='attachment-open'][data-index='0']")
      |> render()

    assert html =~ "egregoros:media-open"
    refute html =~ "open_media"
  end

  test "media viewer renders navigation controls for multi-attachment posts", %{conn: conn} do
    assert {:ok, note} =
             Pipeline.ingest(
               %{
                 "id" => "https://remote.example/objects/with-images",
                 "type" => "Note",
                 "attributedTo" => "https://remote.example/users/bob",
                 "content" => "<p>Hello</p>",
                 "to" => ["https://www.w3.org/ns/activitystreams#Public"],
                 "cc" => ["https://remote.example/users/bob/followers"],
                 "attachment" => [
                   %{
                     "type" => "Document",
                     "mediaType" => "image/png",
                     "name" => "One",
                     "url" => "https://cdn.example/one.png"
                   },
                   %{
                     "type" => "Document",
                     "mediaType" => "image/png",
                     "name" => "Two",
                     "url" => "https://cdn.example/two.png"
                   }
                 ]
               },
               local: false
             )

    {:ok, view, _html} = live(conn, "/?timeline=public")

    assert has_element?(
             view,
             "#post-#{note.id} button[data-role='attachment-open'][data-index='0']"
           )

    assert has_element?(
             view,
             "#post-#{note.id} button[data-role='attachment-open'][data-index='1']"
           )

    prev_html =
      view
      |> element("#media-viewer button[data-role='media-viewer-prev']")
      |> render()

    next_html =
      view
      |> element("#media-viewer button[data-role='media-viewer-next']")
      |> render()

    assert prev_html =~ "egregoros:media-prev"
    refute prev_html =~ "media_prev"
    assert next_html =~ "egregoros:media-next"
    refute next_html =~ "media_next"
  end
end
