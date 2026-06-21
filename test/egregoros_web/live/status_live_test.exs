defmodule EgregorosWeb.StatusLiveTest do
  use EgregorosWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Egregoros.Activities.Note
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Publish
  alias Egregoros.Relationships
  alias Egregoros.TestSupport.Fixtures
  alias Egregoros.Users
  alias Egregoros.Workers.FetchThreadAncestors
  alias Egregoros.Workers.FetchThreadReplies

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

  test "back link returns to the originating timeline when provided via params", %{
    conn: conn,
    user: user
  } do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Hello from status"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}?back_timeline=public")

    assert has_element?(
             view,
             "a[aria-label='Back to timeline'][href*='timeline=public'][href*='restore_scroll=1']"
           )
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

  test "vote_on_poll requires login", %{conn: conn, user: user} do
    {:ok, create} =
      Publish.post_poll(user, "Poll", %{
        "options" => ["A", "B"],
        "expires_in" => 300
      })

    poll = Objects.get_by_ap_id(create.object)
    uuid = uuid_from_ap_id(poll.ap_id)

    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    _html = render_hook(view, "vote_on_poll", %{"poll-id" => poll.id, "choices" => ["0"]})
    assert render(view) =~ "Register to vote on polls."
  end

  test "vote_on_poll surfaces poll voting errors and success messages", %{conn: conn, user: user} do
    {:ok, bob} = Users.create_local_user("poll_voter_bob")

    {:ok, create} =
      Publish.post_poll(user, "Poll", %{
        "options" => ["A", "B"],
        "expires_in" => 300
      })

    poll = Objects.get_by_ap_id(create.object)
    uuid = uuid_from_ap_id(poll.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: bob.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    _html = render_hook(view, "vote_on_poll", %{"poll-id" => poll.id, "choices" => ["0", "1"]})
    assert render(view) =~ "This poll only allows a single choice."

    _html = render_hook(view, "vote_on_poll", %{"poll-id" => poll.id, "choices" => ["99"]})
    assert render(view) =~ "Invalid poll option selected."

    _html = render_hook(view, "vote_on_poll", %{"poll-id" => poll.id, "choices" => "0"})
    assert render(view) =~ "Vote submitted!"

    _html = render_hook(view, "vote_on_poll", %{"poll-id" => poll.id, "choices" => ["1"]})
    assert render(view) =~ "You have already voted on this poll."

    _html = render_hook(view, "vote_on_poll", %{"poll-id" => poll.id})
    assert render(view) =~ "Please select at least one option."
  end

  test "vote_on_poll rejects own polls and expired polls", %{conn: conn, user: user} do
    {:ok, bob} = Users.create_local_user("poll_voter_bob_expired")

    {:ok, create} =
      Publish.post_poll(user, "Poll", %{
        "options" => ["A", "B"],
        "expires_in" => 300
      })

    poll = Objects.get_by_ap_id(create.object)
    expired_at = DateTime.add(DateTime.utc_now(), -3600, :second) |> DateTime.to_iso8601()

    {:ok, expired_poll} =
      Objects.update_object(poll, %{data: Map.put(poll.data, "closed", expired_at)})

    uuid = uuid_from_ap_id(expired_poll.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: bob.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    _html = render_hook(view, "vote_on_poll", %{"poll-id" => expired_poll.id, "choices" => ["0"]})
    assert render(view) =~ "This poll has ended."

    conn = Plug.Test.init_test_session(build_conn(), %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    _html = render_hook(view, "vote_on_poll", %{"poll-id" => expired_poll.id, "choices" => ["0"]})
    assert render(view) =~ "You cannot vote on your own poll."
  end

  test "vote_on_poll handles malformed poll ids without crashing", %{conn: conn, user: user} do
    {:ok, bob} = Users.create_local_user("poll_voter_invalid_id")

    {:ok, create} =
      Publish.post_poll(user, "Poll", %{
        "options" => ["A", "B"],
        "expires_in" => 300
      })

    poll = Objects.get_by_ap_id(create.object)
    uuid = uuid_from_ap_id(poll.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: bob.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    bad_id = "AAAAAAAAAAAAAAAAA-"

    _html = render_hook(view, "vote_on_poll", %{"poll-id" => bad_id, "choices" => ["0"]})
    assert render(view) =~ "Could not submit vote."
  end

  test "reply composer mention autocomplete suggests users", %{conn: conn, user: user} do
    {:ok, note} = Pipeline.ingest(Note.build(user, "Hello from status"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)
    {:ok, _} = Users.create_local_user("bob")

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/@alice/#{uuid}?reply=true")

    _html = render_hook(view, "mention_search", %{"q" => "bo", "scope" => "reply-modal"})
    assert has_element?(view, "[data-role='mention-suggestion']", "@bob")
  end

  test "reply composer mention autocomplete suggestions can be cleared", %{conn: conn, user: user} do
    {:ok, note} = Pipeline.ingest(Note.build(user, "Hello from status"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)
    {:ok, _} = Users.create_local_user("bob")

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/@alice/#{uuid}?reply=true")

    _html = render_hook(view, "mention_search", %{"q" => "bo", "scope" => "reply-modal"})
    assert has_element?(view, "[data-role='mention-suggestion']", "@bob")

    _html = render_hook(view, "mention_clear", %{"scope" => "reply-modal"})
    refute has_element?(view, "[data-role='mention-suggestion']")
  end

  test "reply modal includes mention handles data for frontend prefill when opened via reply param",
       %{
         conn: conn,
         user: user
       } do
    {:ok, bob} = Users.create_local_user("bob")
    {:ok, _carol} = Users.create_local_user("carol")

    assert {:ok, _create} = Publish.post_note(user, "Hi @carol")
    [note] = Objects.list_notes_by_actor(user.ap_id, limit: 1)

    uuid = uuid_from_ap_id(note.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: bob.id})
    {:ok, view, _html} = live(conn, "/@alice/#{uuid}?reply=true")

    assert has_element?(view, "#reply-modal[data-prefill-mention-handles*='@carol']")
  end

  test "reply modal ignores invalid mention tags in frontend prefill data", %{
    conn: conn,
    user: user
  } do
    assert {:ok, note} =
             Pipeline.ingest(
               %{
                 "id" => "https://remote.example/objects/bad-mention",
                 "type" => "Note",
                 "attributedTo" => "https://remote.example/users/bob",
                 "to" => ["https://www.w3.org/ns/activitystreams#Public"],
                 "cc" => [],
                 "content" => "<p>bad mention</p>",
                 "tag" => [
                   %{
                     "type" => "Mention",
                     "href" => "https://remote.example/users/-bad",
                     "name" => "@-bad"
                   }
                 ]
               },
               local: false
             )

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/@bob@remote.example/#{note.id}?reply=true")

    refute has_element?(view, "#reply-modal[data-prefill-mention-handles*='@-bad']")
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

  test "thread view marks the focused post for auto-scroll", %{conn: conn, user: user} do
    assert {:ok, root} = Pipeline.ingest(Note.build(user, "Root"), local: true)

    assert {:ok, reply} =
             Pipeline.ingest(
               Note.build(user, "Reply") |> Map.put("inReplyTo", root.ap_id),
               local: true
             )

    uuid = uuid_from_ap_id(reply.ap_id)

    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    assert has_element?(view, "[data-role='thread-focus'][phx-hook='StatusAutoScroll']")
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

  test "thread view shows reply context links for descendants", %{conn: conn, user: user} do
    {:ok, bob} = Users.create_local_user("bob")

    assert {:ok, root} = Pipeline.ingest(Note.build(user, "Root"), local: true)

    assert {:ok, reply} =
             Pipeline.ingest(
               Note.build(bob, "Reply from bob") |> Map.put("inReplyTo", root.ap_id),
               local: true
             )

    assert {:ok, child} =
             Pipeline.ingest(
               Note.build(user, "Child from alice") |> Map.put("inReplyTo", reply.ap_id),
               local: true
             )

    uuid = uuid_from_ap_id(root.ap_id)

    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    assert has_element?(
             view,
             "[data-role='thread-replying-to'][data-parent-id='post-#{root.id}']",
             "Replying to @alice"
           )

    assert has_element?(
             view,
             "[data-role='thread-replying-to'][data-parent-id='post-#{reply.id}']",
             "Replying to @bob"
           )

    assert has_element?(
             view,
             "[data-role='thread-replying-to'] a[href='#post-#{reply.id}']",
             "Replying to @bob"
           )

    assert has_element?(view, "#post-#{child.id}", "Child from alice")
  end

  test "thread view enqueues fetching missing ancestors and shows a hint when context is incomplete",
       %{conn: conn, user: user} do
    parent_ap_id = "https://remote.example/objects/missing-parent"

    assert {:ok, reply} =
             Pipeline.ingest(
               Note.build(user, "Reply") |> Map.put("inReplyTo", parent_ap_id),
               local: true,
               thread_fetch: true
             )

    uuid = uuid_from_ap_id(reply.ap_id)

    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    assert has_element?(view, "[data-role='thread-missing-context']", "Fetching context")

    assert has_element?(
             view,
             "[data-role='thread-missing-context'] [data-role='skeleton-status-card']"
           )

    assert_enqueued(worker: FetchThreadAncestors, args: %{"start_ap_id" => reply.ap_id})
  end

  test "thread view offers a retry button for missing context", %{conn: conn, user: user} do
    parent_ap_id = "https://remote.example/objects/missing-parent-retry"

    assert {:ok, reply} =
             Pipeline.ingest(
               Note.build(user, "Reply") |> Map.put("inReplyTo", parent_ap_id),
               local: true
             )

    uuid = uuid_from_ap_id(reply.ap_id)

    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    refute has_element?(view, "button[data-role='thread-fetch-context']", "Retry")

    send(view.pid, {:thread_retry_available, :context})
    _ = :sys.get_state(view.pid)

    assert has_element?(view, "button[data-role='thread-fetch-context']", "Retry")

    _html =
      view
      |> element("button[data-role='thread-fetch-context']")
      |> render_click()

    assert render(view) =~ "Queued a context fetch."
  end

  test "status view enqueues a thread replies fetch when the object advertises a replies collection",
       %{
         conn: conn,
         user: user
       } do
    root_id = "https://remote.example/objects/root-with-replies"
    replies_url = root_id <> "/replies"

    assert {:ok, root} =
             Pipeline.ingest(
               %{
                 "id" => root_id,
                 "type" => "Note",
                 "attributedTo" => "https://remote.example/users/bob",
                 "to" => ["https://www.w3.org/ns/activitystreams#Public"],
                 "cc" => [],
                 "content" => "<p>Root</p>",
                 "replies" => %{"id" => replies_url, "type" => "OrderedCollection"}
               },
               local: false
             )

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, _view, _html} = live(conn, "/@bob@remote.example/#{root.id}")

    assert_enqueued(
      worker: FetchThreadReplies,
      args: %{"root_ap_id" => root.ap_id},
      priority: 9
    )
  end

  test "status view does not enqueue a thread replies fetch when replies were checked recently",
       %{
         conn: conn,
         user: user
       } do
    root_id = "https://remote.example/objects/root-checked-recently"
    replies_url = root_id <> "/replies"

    assert {:ok, root} =
             Pipeline.ingest(
               %{
                 "id" => root_id,
                 "type" => "Note",
                 "attributedTo" => "https://remote.example/users/bob",
                 "to" => ["https://www.w3.org/ns/activitystreams#Public"],
                 "cc" => [],
                 "content" => "<p>Root</p>",
                 "replies" => %{"id" => replies_url, "type" => "OrderedCollection"}
               },
               local: false
             )

    assert {:ok, root} =
             Objects.update_object(root, %{thread_replies_checked_at: DateTime.utc_now()})

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@bob@remote.example/#{root.id}")

    assert has_element?(view, "[data-role='thread-replies-empty']", "No replies yet.")
    refute has_element?(view, "[data-role='thread-replies-fetching']")

    refute_enqueued(
      worker: FetchThreadReplies,
      args: %{"root_ap_id" => root.ap_id}
    )
  end

  test "status view enqueues a thread replies refresh when the last check is stale", %{
    conn: conn,
    user: user
  } do
    root_id = "https://remote.example/objects/root-checked-stale"
    replies_url = root_id <> "/replies"
    checked_at = DateTime.add(DateTime.utc_now(), -600, :second)

    assert {:ok, root} =
             Pipeline.ingest(
               %{
                 "id" => root_id,
                 "type" => "Note",
                 "attributedTo" => "https://remote.example/users/bob",
                 "to" => ["https://www.w3.org/ns/activitystreams#Public"],
                 "cc" => [],
                 "content" => "<p>Root</p>",
                 "replies" => %{"id" => replies_url, "type" => "OrderedCollection"}
               },
               local: false
             )

    assert {:ok, root} = Objects.update_object(root, %{thread_replies_checked_at: checked_at})

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@bob@remote.example/#{root.id}")

    assert has_element?(view, "[data-role='thread-replies-empty']", "No replies yet.")

    assert_enqueued(
      worker: FetchThreadReplies,
      args: %{"root_ap_id" => root.ap_id},
      priority: 9
    )
  end

  test "thread view shows a fetching state when replies are being discovered", %{
    conn: conn,
    user: user
  } do
    root_id = "https://remote.example/objects/root-fetching-replies"
    replies_url = root_id <> "/replies"

    assert {:ok, root} =
             Pipeline.ingest(
               %{
                 "id" => root_id,
                 "type" => "Note",
                 "attributedTo" => "https://remote.example/users/bob",
                 "to" => ["https://www.w3.org/ns/activitystreams#Public"],
                 "cc" => [],
                 "content" => "<p>Root</p>",
                 "replies" => %{"id" => replies_url, "type" => "OrderedCollection"}
               },
               local: false
             )

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@bob@remote.example/#{root.id}")

    assert has_element?(view, "[data-role='thread-replies-fetching']", "Fetching replies")
  end

  test "thread view stops showing the fetching skeleton after a replies fetch completes with zero items",
       %{
         conn: conn,
         user: user
       } do
    root_id = "https://remote.example/objects/root-fetches-no-replies"
    replies_url = root_id <> "/replies"

    assert {:ok, root} =
             Pipeline.ingest(
               %{
                 "id" => root_id,
                 "type" => "Note",
                 "attributedTo" => "https://remote.example/users/bob",
                 "to" => ["https://www.w3.org/ns/activitystreams#Public"],
                 "cc" => [],
                 "content" => "<p>Root</p>",
                 "replies" => %{
                   "id" => replies_url,
                   "type" => "OrderedCollection",
                   "totalItems" => 0
                 }
               },
               local: false
             )

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@bob@remote.example/#{root.id}")

    assert has_element?(view, "[data-role='thread-replies-fetching']", "Fetching replies")

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == replies_url

      {:ok,
       %{
         status: 200,
         body: %{
           "id" => replies_url,
           "type" => "OrderedCollectionPage",
           "orderedItems" => []
         },
         headers: []
       }}
    end)

    assert :ok =
             FetchThreadReplies.perform(%Oban.Job{
               args: %{"root_ap_id" => root.ap_id, "max_pages" => 1}
             })

    _ = :sys.get_state(view.pid)

    assert has_element?(view, "[data-role='thread-replies-empty']", "No replies yet.")
    refute has_element?(view, "[data-role='thread-replies-fetching']")
  end

  test "thread view shows skeleton placeholders while fetching replies", %{
    conn: conn,
    user: user
  } do
    root_id = "https://remote.example/objects/root-fetching-skeleton"
    replies_url = root_id <> "/replies"

    assert {:ok, root} =
             Pipeline.ingest(
               %{
                 "id" => root_id,
                 "type" => "Note",
                 "attributedTo" => "https://remote.example/users/bob",
                 "to" => ["https://www.w3.org/ns/activitystreams#Public"],
                 "cc" => [],
                 "content" => "<p>Root</p>",
                 "replies" => %{"id" => replies_url, "type" => "OrderedCollection"}
               },
               local: false
             )

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@bob@remote.example/#{root.id}")

    assert has_element?(
             view,
             "[data-role='thread-replies-fetching'] [data-role='skeleton-status-card']"
           )
  end

  test "thread view offers a retry button while fetching replies", %{conn: conn, user: user} do
    root_id = "https://remote.example/objects/root-fetching-replies-retry"
    replies_url = root_id <> "/replies"

    assert {:ok, root} =
             Pipeline.ingest(
               %{
                 "id" => root_id,
                 "type" => "Note",
                 "attributedTo" => "https://remote.example/users/bob",
                 "to" => ["https://www.w3.org/ns/activitystreams#Public"],
                 "cc" => [],
                 "content" => "<p>Root</p>",
                 "replies" => %{"id" => replies_url, "type" => "OrderedCollection"}
               },
               local: false
             )

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@bob@remote.example/#{root.id}")

    refute has_element?(view, "button[data-role='thread-fetch-replies']", "Retry")

    send(view.pid, {:thread_retry_available, :replies})
    _ = :sys.get_state(view.pid)

    assert has_element?(view, "button[data-role='thread-fetch-replies']", "Retry")

    _html =
      view
      |> element("button[data-role='thread-fetch-replies']")
      |> render_click()

    assert render(view) =~ "Queued a replies fetch."
  end

  test "thread view updates when new replies arrive", %{conn: conn, user: user} do
    assert {:ok, root} = Pipeline.ingest(Note.build(user, "Root"), local: true)
    uuid = uuid_from_ap_id(root.ap_id)

    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")
    assert has_element?(view, "[data-role='thread-replies-empty']", "No replies yet.")

    assert {:ok, _reply} =
             Pipeline.ingest(
               Note.build(user, "Live reply") |> Map.put("inReplyTo", root.ap_id),
               local: true
             )

    _ = :sys.get_state(view.pid)

    refute has_element?(view, "[data-role='thread-replies-empty']")
    assert has_element?(view, "article[data-role='status-card']", "Live reply")
  end

  test "thread view updates when missing ancestors are ingested", %{conn: conn, user: user} do
    parent_ap_id = "https://remote.example/objects/parent"

    assert {:ok, reply} =
             Pipeline.ingest(
               Note.build(user, "Reply") |> Map.put("inReplyTo", parent_ap_id),
               local: true
             )

    uuid = uuid_from_ap_id(reply.ap_id)

    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")
    refute render(view) =~ "Remote parent"
    refute has_element?(view, "[data-role='thread-ancestors']")

    assert {:ok, _remote_parent} =
             Pipeline.ingest(
               %{
                 "id" => parent_ap_id,
                 "type" => "Note",
                 "attributedTo" => "https://remote.example/users/bob",
                 "to" => ["https://www.w3.org/ns/activitystreams#Public"],
                 "cc" => [],
                 "content" => "<p>Remote parent</p>"
               },
               local: false
             )

    _ = :sys.get_state(view.pid)

    assert has_element?(view, "[data-role='thread-ancestors']", "Remote parent")
  end

  test "renders an empty replies state when the thread has no replies", %{conn: conn, user: user} do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Lonely post"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    assert has_element?(view, "[data-role='thread-replies-empty']", "No replies yet.")
  end

  test "signed-in users can reply from the status page", %{conn: conn, user: user} do
    assert {:ok, parent} = Pipeline.ingest(Note.build(user, "Parent post"), local: true)
    uuid = uuid_from_ap_id(parent.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}?reply=true")

    view
    |> form("#reply-modal-form", reply: %{content: "A reply", in_reply_to: parent.ap_id})
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
    |> form("#reply-modal-form",
      reply: %{content: "Remote reply", in_reply_to: remote_parent.ap_id}
    )
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

    assert has_element?(view, "#reply-modal-form[phx-hook='ComposeSettings']")

    assert has_element?(
             view,
             "textarea[data-role='compose-content'][phx-hook='ComposeCharCounter'][data-max-chars='5000']"
           )

    assert has_element?(view, "[data-role='compose-char-counter']", "5000")
    assert has_element?(view, "button[data-role='compose-submit'][disabled]")

    view
    |> form("#reply-modal-form", reply: %{content: "hello"})
    |> render_change()

    assert has_element?(view, "[data-role='compose-char-counter']", "4995")
    refute has_element?(view, "button[data-role='compose-submit'][disabled]")
  end

  test "reply composer renders an emoji picker", %{conn: conn, user: user} do
    assert {:ok, parent} = Pipeline.ingest(Note.build(user, "Parent post"), local: true)
    uuid = uuid_from_ap_id(parent.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}?reply=true")

    assert has_element?(view, "#reply-modal-form [data-role='compose-emoji-picker']")

    assert has_element?(
             view,
             "#reply-modal-form [data-role='compose-emoji-option'][data-emoji='😀']"
           )
  end

  test "reply composer shows who is being replied to", %{conn: conn, user: user} do
    assert {:ok, parent} = Pipeline.ingest(Note.build(user, "Parent post"), local: true)
    uuid = uuid_from_ap_id(parent.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}?reply=true")

    assert has_element?(view, "[data-role='reply-modal-target']", "Replying to @alice")
  end

  test "reply composer popovers are not clipped by overflow hidden", %{conn: conn, user: user} do
    assert {:ok, parent} = Pipeline.ingest(Note.build(user, "Parent post"), local: true)
    uuid = uuid_from_ap_id(parent.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}?reply=true")

    assert has_element?(
             view,
             "#reply-modal [data-role='compose-editor'][class*='overflow-visible']"
           )

    refute has_element?(
             view,
             "#reply-modal [data-role='compose-editor'][class*='overflow-hidden']"
           )
  end

  test "reply modal dialog wrapper does not clip popovers", %{conn: conn, user: user} do
    assert {:ok, parent} = Pipeline.ingest(Note.build(user, "Parent post"), local: true)
    uuid = uuid_from_ap_id(parent.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}?reply=true")

    refute has_element?(view, "#reply-modal-dialog[class*='overflow-hidden']")
  end

  test "visibility menu uses consistent icon sizing", %{conn: conn, user: user} do
    assert {:ok, parent} = Pipeline.ingest(Note.build(user, "Parent post"), local: true)
    uuid = uuid_from_ap_id(parent.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}?reply=true")

    menu = "#reply-modal [data-role='compose-visibility-menu']"

    assert has_element?(view, "#{menu} span.hero-globe-alt.size-5")
    assert has_element?(view, "#{menu} span.hero-link.size-5")
    assert has_element?(view, "#{menu} span.hero-lock-closed.size-5")
    assert has_element?(view, "#{menu} span.hero-envelope.size-5")
  end

  test "status cards render modal reply controls when signed in", %{conn: conn, user: user} do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Replyable"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    assert has_element?(view, "#post-#{note.id} button[data-role='reply']")

    html =
      view
      |> element("#post-#{note.id} button[data-role='reply']")
      |> render()

    assert html =~ "egregoros:reply-open"
    assert html =~ note.ap_id

    assert has_element?(view, "#reply-modal[data-role='reply-modal'][data-state='closed']")
  end

  test "status view does not render reply composer when signed out", %{conn: conn, user: user} do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Replyable"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}?reply=true")
    refute has_element?(view, "#reply-modal")

    _html =
      render_click(view, "create_reply", %{
        "reply" => %{
          "in_reply_to" => note.ap_id,
          "content" => "Hello"
        }
      })

    assert render(view) =~ "Register to reply."
    refute has_element?(view, "#reply-modal")
  end

  test "status view exposes reply prefill data when reply=true", %{conn: conn, user: user} do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Replyable"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}?reply=true")

    assert has_element?(view, "#reply-modal[data-role='reply-modal'][data-state='closed']")
    assert has_element?(view, "#reply-modal[data-prefill-in-reply-to='#{note.ap_id}']")
    assert has_element?(view, "#reply-modal[data-prefill-actor-handle='@alice']")
    assert has_element?(view, "input[data-role='reply-in-reply-to'][value='#{note.ap_id}']")
  end

  test "status view reply prefill mention handles include remote domains", %{
    conn: conn,
    user: user
  } do
    assert {:ok, note} =
             Pipeline.ingest(
               %{
                 "id" => "https://shitposter.world/objects/mention-domain-status",
                 "type" => "Note",
                 "attributedTo" => "https://shitposter.world/users/mrsaturday",
                 "to" => ["https://www.w3.org/ns/activitystreams#Public"],
                 "cc" => [],
                 "content" => "<p>Hi</p>",
                 "tag" => [
                   %{
                     "type" => "Mention",
                     "href" => "https://shitposter.world/users/nerthos",
                     "name" => "@nerthos"
                   },
                   %{
                     "type" => "Mention",
                     "href" => "https://shitposter.world/users/noyoushutthefuckupdad",
                     "name" => "@noyoushutthefuckupdad"
                   }
                 ]
               },
               local: false
             )

    actor_ap_id = "https://shitposter.world/users/mrsaturday"

    %URI{path: path} = URI.parse(actor_ap_id)
    nickname = Path.basename(path)
    handle = nickname <> "@shitposter.world"

    status_path = "/@" <> handle <> "/" <> note.id

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, status_path <> "?reply=true")

    assert has_element?(
             view,
             "#reply-modal[data-prefill-mention-handles*='@nerthos@shitposter.world']"
           )

    assert has_element?(
             view,
             "#reply-modal[data-prefill-mention-handles*='@noyoushutthefuckupdad@shitposter.world']"
           )
  end

  test "question status pages can be rendered and refreshed", %{conn: conn, user: user} do
    poll = %{
      "id" => "https://remote.example/objects/poll-1",
      "type" => "Question",
      "attributedTo" => "https://remote.example/users/bob",
      "context" => "https://remote.example/contexts/poll-1",
      "to" => ["https://www.w3.org/ns/activitystreams#Public"],
      "cc" => [],
      "published" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "content" => "<p>Poll?</p>",
      "oneOf" => [
        %{"type" => "Note", "name" => "Option A", "replies" => %{"totalItems" => 0}},
        %{"type" => "Note", "name" => "Option B", "replies" => %{"totalItems" => 0}}
      ]
    }

    assert {:ok, question} = Pipeline.ingest(poll, local: false)

    handle = "bob@remote.example"
    path = "/@" <> handle <> "/" <> question.id

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, path)

    assert has_element?(view, "article[data-role='status-card']")

    _html = render_click(view, "fetch_thread_context", %{})
    _html = render_click(view, "fetch_thread_replies", %{})

    _html = render_click(view, "toggle_like", %{"id" => question.id})
    assert has_element?(view, "article[data-role='status-card']")
  end

  test "signed-in users can bookmark posts from the status page", %{conn: conn, user: user} do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Bookmark me"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    refute Relationships.get_by_type_actor_object("Bookmark", user.ap_id, note.ap_id)

    view
    |> element("#post-#{note.id} button[data-role='bookmark']")
    |> render_click()

    assert Relationships.get_by_type_actor_object("Bookmark", user.ap_id, note.ap_id)
  end

  test "signed-out users cannot like posts from the status page", %{conn: conn, user: user} do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Like me"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    _html = render_click(view, "toggle_like", %{"id" => note.id})

    assert render(view) =~ "Register to like posts."
  end

  test "status view ignores invalid ids for interaction events", %{conn: conn, user: user} do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Ignore invalid ids"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    _html = render_click(view, "toggle_like", %{"id" => "nope"})
    _html = render_click(view, "toggle_repost", %{"id" => "nope"})
    _html = render_click(view, "toggle_reaction", %{"id" => "nope", "emoji" => "🔥"})
    _html = render_click(view, "toggle_bookmark", %{"id" => "nope"})

    refute render(view) =~ "Register to like posts."
    refute render(view) =~ "Register to repost."
    refute render(view) =~ "Register to react."
    refute render(view) =~ "Register to bookmark posts."
  end

  test "status view rejects delete requests for posts not owned by the user", %{
    conn: conn,
    user: user
  } do
    {:ok, bob} = Users.create_local_user("bob")
    assert {:ok, note} = Pipeline.ingest(Note.build(bob, "Not yours"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@bob/#{uuid}")

    _html = render_click(view, "delete_post", %{"id" => note.id})

    assert render(view) =~ "Could not delete post."
    assert Objects.get(note.id)
  end

  test "status view uses in_reply_to from form params when reply target is not assigned", %{
    conn: conn,
    user: user
  } do
    assert {:ok, parent} = Pipeline.ingest(Note.build(user, "Parent post"), local: true)
    uuid = uuid_from_ap_id(parent.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    view
    |> form("#reply-modal-form", reply: %{content: "Param reply", in_reply_to: parent.ap_id})
    |> render_submit()

    assert has_element?(view, "article", "Param reply")
  end

  test "status view ignores post updates not related to the current thread", %{
    conn: conn,
    user: user
  } do
    assert {:ok, parent} = Pipeline.ingest(Note.build(user, "Thread parent"), local: true)
    uuid = uuid_from_ap_id(parent.ap_id)

    assert {:ok, other} = Pipeline.ingest(Note.build(user, "Other post"), local: true)

    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")
    assert has_element?(view, "article[data-role='status-card']", "Thread parent")

    send(view.pid, {:post_updated, other})
    _ = :sys.get_state(view.pid)

    assert has_element?(view, "article[data-role='status-card']", "Thread parent")
  end

  test "signed-out users cannot bookmark posts from the status page", %{conn: conn, user: user} do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Bookmark me"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    _html = render_click(view, "toggle_bookmark", %{"id" => note.id})

    assert render(view) =~ "Register to bookmark posts."
  end

  test "signed-in users can delete their own status and are navigated back to the timeline", %{
    conn: conn,
    user: user
  } do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Delete me"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    view
    |> element("#post-#{note.id} button[data-role='delete-post-confirm']")
    |> render_click()

    assert Objects.get(note.id) == nil
    assert_redirect(view, "/?timeline=home&restore_scroll=1")
  end

  test "deleting a reply refreshes the thread without navigating away", %{conn: conn, user: user} do
    assert {:ok, root} = Pipeline.ingest(Note.build(user, "Root"), local: true)

    assert {:ok, reply} =
             Pipeline.ingest(
               Note.build(user, "Reply") |> Map.put("inReplyTo", root.ap_id),
               local: true
             )

    uuid = uuid_from_ap_id(root.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    assert has_element?(view, "#post-#{reply.id}", "Reply")

    view
    |> element("#post-#{reply.id} button[data-role='delete-post-confirm']")
    |> render_click()

    assert Objects.get(reply.id) == nil
    refute has_element?(view, "#post-#{reply.id}")
    assert has_element?(view, "#post-#{root.id}")
  end

  test "signed-out users cannot delete posts from the status view", %{conn: conn, user: user} do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Hello"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    _html = render_click(view, "delete_post", %{"id" => note.id})

    assert render(view) =~ "Register to delete posts."
    assert Objects.get(note.id)
  end

  test "reply content warning toggle opens and closes the CW field", %{conn: conn, user: user} do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "CW toggle"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}?reply=true")

    assert has_element?(view, "[data-role='compose-cw'][data-state='closed']")

    _html =
      render_change(view, "reply_change", %{
        "reply" => %{"ui_cw_open" => "true"}
      })

    assert has_element?(view, "[data-role='compose-cw'][data-state='open']")
  end

  test "status view handles unrelated messages without crashing", %{conn: conn, user: user} do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Hello"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    send(view.pid, :unrelated)
    _ = :sys.get_state(view.pid)

    assert has_element?(view, "article[data-role='status-card']", "Hello")
  end

  test "replying rejects content longer than 5000 characters", %{conn: conn, user: user} do
    assert {:ok, parent} = Pipeline.ingest(Note.build(user, "Parent post"), local: true)
    uuid = uuid_from_ap_id(parent.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}?reply=true")

    too_long = String.duplicate("a", 5001)

    view
    |> form("#reply-modal-form", reply: %{content: too_long})
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
      assert passed_user.id == user.id
      assert passed_upload.filename == "photo.png"
      assert passed_upload.content_type == "image/png"
      {:ok, "/uploads/media/#{passed_user.id}/photo.png"}
    end)

    assert render_upload(upload, "photo.png") =~ "100%"

    view
    |> form("#reply-modal-form", reply: %{content: "Reply with media", in_reply_to: parent.ap_id})
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
      file_input(view, "#reply-modal-form", :reply_media, [
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
      file_input(view, "#reply-modal-form", :reply_media, [
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

  test "single-attachment statuses use a single-column attachment layout", %{
    conn: conn,
    user: user
  } do
    note =
      Note.build(user, "With one image")
      |> Map.put("attachment", [
        %{
          "mediaType" => "image/png",
          "name" => "only",
          "url" => [%{"href" => "/uploads/only.png", "mediaType" => "image/png"}]
        }
      ])

    assert {:ok, object} = Pipeline.ingest(note, local: true)
    uuid = uuid_from_ap_id(object.ap_id)

    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    assert has_element?(
             view,
             "#post-#{object.id} [data-role='attachments'][data-layout='single']"
           )
  end

  test "multi-attachment statuses use a grid attachment layout", %{conn: conn, user: user} do
    note =
      Note.build(user, "With two images")
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

    assert has_element?(
             view,
             "#post-#{object.id} [data-role='attachments'][data-layout='grid']"
           )
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

  test "signed-in users can remove reply uploads before posting", %{conn: conn, user: user} do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Parent post"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}?reply=true")

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
      file_input(view, "#reply-modal-form", :reply_media, [
        %{
          last_modified: 1_694_171_879_000,
          name: "photo.png",
          content: content,
          type: "image/png"
        }
      ])

    assert render_upload(upload, "photo.png", 10) =~ "10%"

    view
    |> form("#reply-modal-form",
      reply: %{content: "Reply while uploading", in_reply_to: note.ap_id}
    )
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
      file_input(view, "#reply-modal-form", :reply_media, [
        %{
          last_modified: 1_694_171_879_000,
          name: "photo.png",
          content: content,
          type: "image/png"
        }
      ])

    expect(Egregoros.MediaStorage.Mock, :store_media, fn passed_user, passed_upload ->
      assert passed_user.id == user.id
      assert passed_upload.filename == "photo.png"
      {:error, :storage_failed}
    end)

    assert render_upload(upload, "photo.png") =~ "100%"

    view
    |> form("#reply-modal-form", reply: %{content: "Reply with media", in_reply_to: note.ap_id})
    |> render_submit()

    assert render(view) =~ "Could not upload attachment."
  end

  test "rejects empty replies", %{conn: conn, user: user} do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Parent post"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}?reply=true")

    view
    |> form("#reply-modal-form", reply: %{content: "", in_reply_to: note.ap_id})
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
