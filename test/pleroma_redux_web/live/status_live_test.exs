defmodule PleromaReduxWeb.StatusLiveTest do
  use PleromaReduxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PleromaRedux.Activities.Note
  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.TestSupport.Fixtures
  alias PleromaRedux.Users

  setup do
    {:ok, user} = Users.create_local_user("alice")
    %{user: user}
  end

  test "renders a local status permalink page", %{conn: conn, user: user} do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Hello from status"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    assert has_element?(view, "article[data-role='status-card']", "Hello from status")
  end

  test "does not render direct messages on public status permalinks", %{conn: conn, user: user} do
    dm =
      user
      |> Note.build("Secret DM")
      |> Map.put("to", [])
      |> Map.put("cc", [])

    assert {:ok, note} = Pipeline.ingest(dm, local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    assert render(view) =~ "Post not found"
    refute render(view) =~ "Secret DM"
  end

  test "redirects to the canonical nickname for local status permalinks", %{
    conn: conn,
    user: user
  } do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Hello from status"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    assert {:error, {kind, %{to: to}}} = live(conn, "/@not-alice/#{uuid}")
    assert kind in [:redirect, :live_redirect]
    assert to == "/@alice/#{uuid}"
  end

  test "redirects to the canonical nickname for remote status permalinks", %{conn: conn} do
    assert {:ok, remote_parent} =
             Pipeline.ingest(
               %{
                 "id" => "https://remote.example/objects/parent",
                 "type" => "Note",
                 "attributedTo" => "https://remote.example/users/bob",
                 "to" => ["https://www.w3.org/ns/activitystreams#Public"],
                 "cc" => [],
                 "content" => "<p>Remote parent</p>"
               },
               local: false
             )

    assert {:error, {kind, %{to: to}}} = live(conn, "/@not-bob/#{remote_parent.id}")
    assert kind in [:redirect, :live_redirect]
    assert to == "/@bob@remote.example/#{remote_parent.id}"
  end

  test "renders thread context around the status", %{conn: conn, user: user} do
    assert {:ok, root} = Pipeline.ingest(Note.build(user, "Root"), local: true)

    assert {:ok, reply} =
             Pipeline.ingest(
               Note.build(user, "Reply") |> Map.put("inReplyTo", root.ap_id),
               local: true
             )

    assert {:ok, _child} =
             Pipeline.ingest(
               Note.build(user, "Child") |> Map.put("inReplyTo", reply.ap_id),
               local: true
             )

    uuid = uuid_from_ap_id(reply.ap_id)

    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    html = render(view)

    assert html =~ "Root"
    assert html =~ "Reply"
    assert html =~ "Child"

    root_index = binary_index!(html, "Root")
    reply_index = binary_index!(html, "Reply")
    child_index = binary_index!(html, "Child")

    assert root_index < reply_index
    assert reply_index < child_index
  end

  test "renders descendant replies with depth indicators", %{conn: conn, user: user} do
    assert {:ok, root} = Pipeline.ingest(Note.build(user, "Root"), local: true)

    assert {:ok, reply} =
             Pipeline.ingest(
               Note.build(user, "Reply") |> Map.put("inReplyTo", root.ap_id),
               local: true
             )

    assert {:ok, _child} =
             Pipeline.ingest(
               Note.build(user, "Child") |> Map.put("inReplyTo", reply.ap_id),
               local: true
             )

    uuid = uuid_from_ap_id(root.ap_id)

    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    assert has_element?(view, "[data-role='thread-descendant'][data-depth='1']", "Reply")
    assert has_element?(view, "[data-role='thread-descendant'][data-depth='2']", "Child")
  end

  test "signed-in users can reply from the status page", %{conn: conn, user: user} do
    assert {:ok, parent} = Pipeline.ingest(Note.build(user, "Parent post"), local: true)
    uuid = uuid_from_ap_id(parent.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}?reply=true")

    view
    |> form("#reply-form", reply: %{content: "A reply"})
    |> render_submit()

    assert has_element?(view, "article", "A reply")

    [reply] = Objects.list_replies_to(parent.ap_id, limit: 1)
    assert reply.data["inReplyTo"] == parent.ap_id
  end

  test "signed-in users can reply to remote posts from the status page", %{conn: conn, user: user} do
    assert {:ok, remote_parent} =
             Pipeline.ingest(
               %{
                 "id" => "https://remote.example/objects/parent",
                 "type" => "Note",
                 "attributedTo" => "https://remote.example/users/bob",
                 "to" => ["https://www.w3.org/ns/activitystreams#Public"],
                 "cc" => [],
                 "content" => "<p>Remote parent</p>"
               },
               local: false
             )

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@bob@remote.example/#{remote_parent.id}?reply=true")

    view
    |> form("#reply-form", reply: %{content: "Remote reply"})
    |> render_submit()

    assert has_element?(view, "article", "Remote reply")

    [reply] = Objects.list_replies_to(remote_parent.ap_id, limit: 1)
    assert reply.data["inReplyTo"] == remote_parent.ap_id
  end

  test "reply character counter counts down while typing", %{conn: conn, user: user} do
    assert {:ok, parent} = Pipeline.ingest(Note.build(user, "Parent post"), local: true)
    uuid = uuid_from_ap_id(parent.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}?reply=true")

    assert has_element?(
             view,
             "textarea[data-role='compose-content'][phx-hook='ComposeCharCounter'][data-max-chars='5000']"
           )

    assert has_element?(view, "[data-role='compose-char-counter']", "5000")
    assert has_element?(view, "button[data-role='compose-submit'][disabled]")

    view
    |> form("#reply-form", reply: %{content: "hello"})
    |> render_change()

    assert has_element?(view, "[data-role='compose-char-counter']", "4995")
    refute has_element?(view, "button[data-role='compose-submit'][disabled]")
  end

  test "reply composer renders an emoji picker", %{conn: conn, user: user} do
    assert {:ok, parent} = Pipeline.ingest(Note.build(user, "Parent post"), local: true)
    uuid = uuid_from_ap_id(parent.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}?reply=true")

    assert has_element?(view, "#reply-form [data-role='compose-emoji-picker']")

    assert has_element?(
             view,
             "#reply-form [data-role='compose-emoji-option'][data-emoji='😀']"
           )
  end

  test "replying rejects content longer than 5000 characters", %{conn: conn, user: user} do
    assert {:ok, parent} = Pipeline.ingest(Note.build(user, "Parent post"), local: true)
    uuid = uuid_from_ap_id(parent.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}?reply=true")

    too_long = String.duplicate("a", 5001)

    view
    |> form("#reply-form", reply: %{content: too_long})
    |> render_submit()

    assert render(view) =~ "Reply is too long."
    assert Objects.list_replies_to(parent.ap_id, limit: 10) == []
  end

  test "signed-in users can attach media when replying", %{conn: conn, user: user} do
    assert {:ok, parent} = Pipeline.ingest(Note.build(user, "Parent post"), local: true)
    uuid = uuid_from_ap_id(parent.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}?reply=true")

    fixture_path = Fixtures.path!("DSCN0010.png")
    content = File.read!(fixture_path)

    upload =
      file_input(view, "#reply-form", :reply_media, [
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
    |> form("#reply-form", reply: %{content: "Reply with media"})
    |> render_submit()

    [reply] = Objects.list_replies_to(parent.ap_id, limit: 1)

    assert has_element?(view, "#post-#{reply.id} img[data-role='attachment']")
  end

  test "reply composer renders video upload previews", %{conn: conn, user: user} do
    assert {:ok, parent} = Pipeline.ingest(Note.build(user, "Parent post"), local: true)
    uuid = uuid_from_ap_id(parent.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}?reply=true")

    upload =
      file_input(view, "#reply-form", :reply_media, [
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

  test "reply composer renders audio upload previews", %{conn: conn, user: user} do
    assert {:ok, parent} = Pipeline.ingest(Note.build(user, "Parent post"), local: true)
    uuid = uuid_from_ap_id(parent.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}?reply=true")

    upload =
      file_input(view, "#reply-form", :reply_media, [
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

  test "signed-in users can like posts from the status page", %{conn: conn, user: user} do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Like me"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    refute Objects.get_by_type_actor_object("Like", user.ap_id, note.ap_id)

    view
    |> element("#post-#{note.id} button[data-role='like']")
    |> render_click()

    assert Objects.get_by_type_actor_object("Like", user.ap_id, note.ap_id)
    assert has_element?(view, "#post-#{note.id} button[data-role='like']", "Unlike")
  end

  test "signed-in users can repost posts from the status page", %{conn: conn, user: user} do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Boost me"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    refute Objects.get_by_type_actor_object("Announce", user.ap_id, note.ap_id)

    view
    |> element("#post-#{note.id} button[data-role='repost']")
    |> render_click()

    assert Objects.get_by_type_actor_object("Announce", user.ap_id, note.ap_id)
    assert has_element?(view, "#post-#{note.id} button[data-role='repost']", "Unrepost")
  end

  test "signed-in users can react to posts from the status page", %{conn: conn, user: user} do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "React to me"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

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

  test "renders a not-found state when the status cannot be loaded", %{conn: conn} do
    assert {:ok, view, html} = live(conn, "/@alice/missing")

    assert html =~ "Post not found"
    assert render(view) =~ "Post not found"
  end

  test "shows feedback when copying a status permalink", %{conn: conn, user: user} do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Copy me"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    view
    |> element("#post-#{note.id} button[data-role='copy-link']")
    |> render_click()

    assert render(view) =~ "Copied link to clipboard."
  end

  test "status media viewer controls are wired client-side without server roundtrips", %{
    conn: conn,
    user: user
  } do
    note =
      Note.build(user, "With images")
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
    uuid = uuid_from_ap_id(object.ap_id)

    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    assert has_element?(view, "#media-viewer[data-role='media-viewer'][data-state='closed']")

    html =
      view
      |> element("#post-#{object.id} button[data-role='attachment-open'][data-index='0']")
      |> render()

    assert html =~ "predux:media-open"
    refute html =~ "open_media"

    prev_html =
      view
      |> element("#media-viewer [data-role='media-viewer-prev']")
      |> render()

    next_html =
      view
      |> element("#media-viewer [data-role='media-viewer-next']")
      |> render()

    assert prev_html =~ "predux:media-prev"
    refute prev_html =~ "media_prev"
    assert next_html =~ "predux:media-next"
    refute next_html =~ "media_next"

    close_html =
      view
      |> element("#media-viewer [data-role='media-viewer-close']")
      |> render()

    assert close_html =~ "predux:media-close"
    refute close_html =~ "close_media"
  end

  test "signed-in users can open and close the reply composer and changes persist", %{
    conn: conn,
    user: user
  } do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Parent post"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    assert has_element?(view, "#reply-form[data-state='closed']")

    view
    |> element("button[data-role='reply-open']")
    |> render_click()

    assert has_element?(view, "#reply-form[data-state='open']")

    view
    |> form("#reply-form", reply: %{content: "Typing..."})
    |> render_change()

    assert render(view) =~ "Typing..."

    view
    |> element("button[data-role='reply-close']")
    |> render_click()

    assert has_element?(view, "button[data-role='reply-open']")
    assert has_element?(view, "#reply-form[data-state='closed']")
  end

  test "signed-in users can remove reply uploads before posting", %{conn: conn, user: user} do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Parent post"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    view
    |> element("button[data-role='reply-open']")
    |> render_click()

    fixture_path = Fixtures.path!("DSCN0010.png")
    content = File.read!(fixture_path)

    upload =
      file_input(view, "#reply-form", :reply_media, [
        %{
          last_modified: 1_694_171_879_000,
          name: "photo.png",
          content: content,
          size: byte_size(content),
          type: "image/png"
        }
      ])

    assert render_upload(upload, "photo.png") =~ "100%"
    assert has_element?(view, "[data-role='media-entry']")

    view
    |> element("[data-role='media-entry'] button[phx-click='cancel_reply_media']")
    |> render_click()

    refute has_element?(view, "[data-role='media-entry']")
  end

  test "blocks posting while reply uploads are still in flight", %{conn: conn, user: user} do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Parent post"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}?reply=true")

    fixture_path = Fixtures.path!("DSCN0010.png")
    content = File.read!(fixture_path)

    upload =
      file_input(view, "#reply-form", :reply_media, [
        %{
          last_modified: 1_694_171_879_000,
          name: "photo.png",
          content: content,
          type: "image/png"
        }
      ])

    assert render_upload(upload, "photo.png", 10) =~ "10%"

    view
    |> form("#reply-form", reply: %{content: "Reply while uploading"})
    |> render_submit()

    assert render(view) =~ "Wait for attachments to finish uploading."
  end

  test "shows feedback when reply attachments fail to store", %{conn: conn, user: user} do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Parent post"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}?reply=true")

    fixture_path = Fixtures.path!("DSCN0010.png")
    content = File.read!(fixture_path)

    upload =
      file_input(view, "#reply-form", :reply_media, [
        %{
          last_modified: 1_694_171_879_000,
          name: "photo.png",
          content: content,
          type: "image/png"
        }
      ])

    expect(PleromaRedux.MediaStorage.Mock, :store_media, fn passed_user, passed_upload ->
      assert passed_user.id == user.id
      assert passed_upload.filename == "photo.png"
      {:error, :storage_failed}
    end)

    assert render_upload(upload, "photo.png") =~ "100%"

    view
    |> form("#reply-form", reply: %{content: "Reply with media"})
    |> render_submit()

    assert render(view) =~ "Could not upload attachment."
  end

  test "rejects empty replies", %{conn: conn, user: user} do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Parent post"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}?reply=true")

    view
    |> form("#reply-form", reply: %{content: ""})
    |> render_submit()

    assert render(view) =~ "Reply can&#39;t be empty."
  end

  defp uuid_from_ap_id(ap_id) when is_binary(ap_id) do
    case URI.parse(ap_id) do
      %URI{path: path} when is_binary(path) and path != "" -> Path.basename(path)
      _ -> Path.basename(ap_id)
    end
  end

  defp binary_index!(binary, pattern) when is_binary(binary) and is_binary(pattern) do
    case :binary.match(binary, pattern) do
      {index, _length} -> index
      :nomatch -> raise ArgumentError, "pattern not found: #{inspect(pattern)}"
    end
  end
end
