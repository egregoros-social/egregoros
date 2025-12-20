defmodule PleromaReduxWeb.TimelineLiveTest do
  use PleromaReduxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PleromaRedux.Activities.Follow
  alias PleromaRedux.Activities.Note
  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Relationships
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
  end

  test "following list is not part of the compose panel", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#compose-panel")
    assert has_element?(view, "#following-panel")
    refute has_element?(view, "#compose-panel #following-panel")
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

    refute has_element?(view, "#compose-overlay")

    view
    |> element("button[data-role='compose-open']")
    |> render_click()

    assert has_element?(view, "#compose-overlay")

    view
    |> element("button[data-role='compose-close']")
    |> render_click()

    refute has_element?(view, "#compose-overlay")
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

  test "posting with an attachment renders it in the timeline", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    fixture_path = Path.expand("pleroma-old/test/fixtures/DSCN0010.png", File.cwd!())
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

    assert has_element?(view, "[data-role='compose-add-media']", "Add media")
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

  test "posting with only an attachment is allowed", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    fixture_path = Path.expand("pleroma-old/test/fixtures/DSCN0010.png", File.cwd!())
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

  test "unfollowing removes the follow from the UI", %{conn: conn, user: user} do
    {:ok, remote} =
      Users.create_user(%{
        nickname: "bob",
        ap_id: "https://remote.example/users/bob",
        inbox: "https://remote.example/users/bob/inbox",
        outbox: "https://remote.example/users/bob/outbox",
        public_key: "PUB",
        private_key: nil,
        local: false
      })

    assert {:ok, _follow_object} = Pipeline.ingest(Follow.build(user, remote), local: true)

    assert %{} =
             relationship =
             Relationships.get_by_type_actor_object("Follow", user.ap_id, remote.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#following-#{relationship.id}")

    view
    |> element("#following-#{relationship.id} button[data-role='unfollow']")
    |> render_click()

    assert Relationships.get(relationship.id) == nil
    refute has_element?(view, "#following-#{relationship.id}")
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

    refute has_element?(view, "[data-role='media-viewer']")

    view
    |> element("#post-#{note.id} button[data-role='attachment-open'][data-index='0']")
    |> render_click()

    assert has_element?(view, "[data-role='media-viewer']")
    assert has_element?(view, "[data-role='media-viewer'] img[src='https://cdn.example/image.png']")

    view
    |> element("button[data-role='media-viewer-close']")
    |> render_click()

    refute has_element?(view, "[data-role='media-viewer']")
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

    assert has_element?(view, "[data-role='media-viewer']")

    _html = render_keydown(view, "media_keydown", %{"key" => "Escape"})

    refute has_element?(view, "[data-role='media-viewer']")
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

    assert has_element?(view, "[data-role='media-viewer'] img[src='https://cdn.example/one.png']")

    _html = render_keydown(view, "media_keydown", %{"key" => "ArrowRight"})

    assert has_element?(view, "[data-role='media-viewer'] img[src='https://cdn.example/two.png']")

    _html = render_keydown(view, "media_keydown", %{"key" => "ArrowLeft"})

    assert has_element?(view, "[data-role='media-viewer'] img[src='https://cdn.example/one.png']")
  end
end
