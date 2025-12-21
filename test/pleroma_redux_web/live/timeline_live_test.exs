defmodule PleromaReduxWeb.TimelineLiveTest do
  use PleromaReduxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PleromaRedux.Activities.Note
  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.TestSupport.Fixtures
  alias PleromaRedux.Timeline
  alias PleromaRedux.Users

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
                 "content" => "<p>ok</p><script>alert(1)</script>"
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

    expect(PleromaRedux.MediaStorage.Mock, :store_media, fn passed_user, passed_upload ->
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

    assert has_element?(view, "[data-role='compose-editor']")
    assert has_element?(view, "[data-role='compose-toolbar']")
    assert has_element?(view, "[data-role='compose-add-media'][aria-label='Add media']")
    assert has_element?(view, "[data-role='compose-add-media'] input[type='file']")

    html =
      view
      |> element("[data-role='compose-add-media']")
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

    expect(PleromaRedux.MediaStorage.Mock, :store_media, fn passed_user, passed_upload ->
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

    expect(PleromaRedux.MediaStorage.Mock, :store_media, fn passed_user, passed_upload ->
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

  test "clicking an image attachment opens a media viewer", %{conn: conn} do
    assert {:ok, note} =
             Pipeline.ingest(
               %{
                 "id" => "https://remote.example/objects/with-image",
                 "type" => "Note",
                 "attributedTo" => "https://remote.example/users/bob",
                 "content" => "<p>Hello</p>",
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

    view
    |> element("#post-#{note.id} button[data-role='attachment-open'][data-index='0']")
    |> render_click()

    assert has_element?(view, "#media-viewer[data-role='media-viewer'][data-state='open']")

    assert has_element?(
             view,
             "#media-viewer[data-state='open'] #media-viewer-dialog[phx-hook='Phoenix.FocusWrap']"
           )

    assert has_element?(
             view,
             "[data-role='media-viewer-slide'][data-state='active'] img[src='https://cdn.example/image.png']"
           )

    view
    |> element("button[data-role='media-viewer-close']")
    |> render_click()

    assert has_element?(view, "#media-viewer[data-role='media-viewer'][data-state='closed']")
  end

  test "media viewer renders video attachments", %{conn: conn} do
    assert {:ok, note} =
             Pipeline.ingest(
               %{
                 "id" => "https://remote.example/objects/with-video-viewer",
                 "type" => "Note",
                 "attributedTo" => "https://remote.example/users/bob",
                 "content" => "<p>Hello</p>",
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

    view
    |> element("#post-#{note.id} button[data-role='attachment-open'][data-index='0']")
    |> render_click()

    assert has_element?(
             view,
             "[data-role='media-viewer-slide'][data-state='active'] video[data-role='media-viewer-item']"
           )

    assert has_element?(
             view,
             "[data-role='media-viewer-slide'][data-state='active'] source[src='https://cdn.example/clip.mp4']"
           )
  end

  test "media viewer renders audio attachments", %{conn: conn} do
    assert {:ok, note} =
             Pipeline.ingest(
               %{
                 "id" => "https://remote.example/objects/with-audio-viewer",
                 "type" => "Note",
                 "attributedTo" => "https://remote.example/users/bob",
                 "content" => "<p>Hello</p>",
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

    view
    |> element("#post-#{note.id} button[data-role='attachment-open'][data-index='0']")
    |> render_click()

    assert has_element?(
             view,
             "[data-role='media-viewer-slide'][data-state='active'] audio[data-role='media-viewer-item']"
           )

    assert has_element?(
             view,
             "[data-role='media-viewer-slide'][data-state='active'] source[src='https://cdn.example/clip.ogg']"
           )
  end

  test "media viewer closes on escape", %{conn: conn} do
    assert {:ok, note} =
             Pipeline.ingest(
               %{
                 "id" => "https://remote.example/objects/with-image-escape",
                 "type" => "Note",
                 "attributedTo" => "https://remote.example/users/bob",
                 "content" => "<p>Hello</p>",
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

    view
    |> element("#post-#{note.id} button[data-role='attachment-open'][data-index='0']")
    |> render_click()

    assert has_element?(view, "#media-viewer[data-role='media-viewer'][data-state='open']")

    _html = render_keydown(view, "media_keydown", %{"key" => "Escape"})

    assert has_element?(view, "#media-viewer[data-role='media-viewer'][data-state='closed']")
  end

  test "media viewer can navigate between image attachments", %{conn: conn} do
    assert {:ok, note} =
             Pipeline.ingest(
               %{
                 "id" => "https://remote.example/objects/with-images",
                 "type" => "Note",
                 "attributedTo" => "https://remote.example/users/bob",
                 "content" => "<p>Hello</p>",
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

    view
    |> element("#post-#{note.id} button[data-role='attachment-open'][data-index='0']")
    |> render_click()

    assert has_element?(
             view,
             "[data-role='media-viewer-slide'][data-state='active'] img[src='https://cdn.example/one.png']"
           )

    _html = render_keydown(view, "media_keydown", %{"key" => "ArrowRight"})

    assert has_element?(
             view,
             "[data-role='media-viewer-slide'][data-state='active'] img[src='https://cdn.example/two.png']"
           )

    _html = render_keydown(view, "media_keydown", %{"key" => "ArrowLeft"})

    assert has_element?(
             view,
             "[data-role='media-viewer-slide'][data-state='active'] img[src='https://cdn.example/one.png']"
           )
  end
end
