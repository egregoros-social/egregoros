defmodule EgregorosWeb.TimelineLiveTest do
  use EgregorosWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Egregoros.Activities.Announce
  alias Egregoros.Activities.Follow
  alias Egregoros.Activities.Like
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

  test "posting shows toast feedback", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    view
    |> form("#timeline-form", post: %{content: "Hello world"})
    |> render_submit()

    assert render(view) =~ "Posted."
  end

  test "posting a poll creates a Question", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    _html = render_click(view, "toggle_compose_poll", %{})

    view
    |> form("#timeline-form",
      post: %{
        content: "Pick one",
        poll: %{"options" => ["Red", "Blue"], "multiple" => "false", "expires_in" => 3600}
      }
    )
    |> render_submit()

    [poll | _] = Objects.list_public_statuses(limit: 1)

    assert poll.type == "Question"
    assert Enum.map(poll.data["oneOf"], & &1["name"]) == ["Red", "Blue"]
  end

  test "poll option events respect min/max limits", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    _html = render_click(view, "toggle_compose_poll", %{})

    socket = :sys.get_state(view.pid).socket
    poll_options = socket.assigns.form.params |> get_in(["poll", "options"]) |> List.wrap()

    assert length(poll_options) == 2

    _html = render_click(view, "poll_add_option", %{})
    _html = render_click(view, "poll_add_option", %{})
    _html = render_click(view, "poll_add_option", %{})

    socket = :sys.get_state(view.pid).socket
    poll_options = socket.assigns.form.params |> get_in(["poll", "options"]) |> List.wrap()

    assert length(poll_options) == 4

    _html = render_click(view, "poll_remove_option", %{"index" => "nope"})

    socket = :sys.get_state(view.pid).socket
    poll_options = socket.assigns.form.params |> get_in(["poll", "options"]) |> List.wrap()

    assert length(poll_options) == 4

    _html = render_click(view, "poll_remove_option", %{"index" => "0"})
    _html = render_click(view, "poll_remove_option", %{"index" => "0"})
    _html = render_click(view, "poll_remove_option", %{"index" => "0"})

    socket = :sys.get_state(view.pid).socket
    poll_options = socket.assigns.form.params |> get_in(["poll", "options"]) |> List.wrap()

    assert length(poll_options) == 2
  end

  test "posting a poll with blank options shows a validation error", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    _html = render_click(view, "toggle_compose_poll", %{})

    view
    |> form("#timeline-form",
      post: %{
        content: "Pick one",
        poll: %{"options" => ["", "Blue"], "multiple" => "false", "expires_in" => 3600}
      }
    )
    |> render_submit()

    assert Objects.list_public_statuses(limit: 1) == []
    assert has_element?(view, "[data-role='compose-error']", "Poll options cannot be blank.")
  end

  test "handle_info post_deleted removes matching pending post", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    _html = render_hook(view, "timeline_at_top", %{"at_top" => "false"})

    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Gonna delete"), local: true)

    send(view.pid, {:post_created, note})
    _ = :sys.get_state(view.pid)

    socket = :sys.get_state(view.pid).socket
    assert socket.assigns.pending_posts == [note]

    send(view.pid, {:post_deleted, %{id: note.id}})
    _ = :sys.get_state(view.pid)

    socket = :sys.get_state(view.pid).socket
    assert socket.assigns.pending_posts == []
  end

  test "toggling the poll panel off clears poll params", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    _html = render_click(view, "toggle_compose_poll", %{})

    socket = :sys.get_state(view.pid).socket
    assert socket.assigns.compose_poll_open?

    assert Map.has_key?(socket.assigns.form.params, "poll")

    _html = render_click(view, "toggle_compose_poll", %{})

    socket = :sys.get_state(view.pid).socket
    refute socket.assigns.compose_poll_open?

    refute Map.has_key?(socket.assigns.form.params, "poll")
  end

  test "posting a direct poll without recipients shows an error instead of crashing", %{
    conn: conn,
    user: user
  } do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    _html = render_click(view, "toggle_compose_poll", %{})

    view
    |> form("#timeline-form",
      post: %{
        content: "Pick one",
        visibility: "direct",
        poll: %{
          "options" => ["Red", "Blue"],
          "multiple" => "false",
          "expires_in" => 3600
        }
      }
    )
    |> render_submit()

    assert has_element?(view, "[data-role='compose-error']", "Invalid poll.")
  end

  test "vote_on_poll requires login and a selected option", %{conn: conn, user: user} do
    {:ok, create} =
      Publish.post_poll(user, "Poll", %{
        "options" => ["A", "B"],
        "expires_in" => 300
      })

    poll = Objects.get_by_ap_id(create.object)

    {:ok, guest_view, _html} = live(conn, "/")

    _html = render_hook(guest_view, "vote_on_poll", %{"poll-id" => poll.id, "choices" => ["0"]})
    assert render(guest_view) =~ "Register to vote on polls."

    {:ok, bob} = Users.create_local_user("poll_vote_requires_choice")

    conn = Plug.Test.init_test_session(conn, %{user_id: bob.id})
    {:ok, view, _html} = live(conn, "/")

    _html = render_hook(view, "vote_on_poll", %{"poll-id" => poll.id, "feed_id" => poll.id})
    assert render(view) =~ "Please select at least one option."
  end

  test "vote_on_poll surfaces poll vote errors and success messages", %{conn: conn, user: user} do
    {:ok, bob} = Users.create_local_user("poll_vote_errors_bob")

    {:ok, create} =
      Publish.post_poll(user, "Poll", %{
        "options" => ["A", "B"],
        "expires_in" => 300
      })

    poll = Objects.get_by_ap_id(create.object)

    conn = Plug.Test.init_test_session(conn, %{user_id: bob.id})
    {:ok, view, _html} = live(conn, "/")

    _html =
      render_hook(view, "vote_on_poll", %{
        "poll-id" => poll.id,
        "feed_id" => poll.id,
        "choices" => ["0", "1"]
      })

    assert render(view) =~ "This poll only allows a single choice."

    _html =
      render_hook(view, "vote_on_poll", %{
        "poll-id" => poll.id,
        "feed_id" => poll.id,
        "choices" => ["99"]
      })

    assert render(view) =~ "Invalid poll option selected."

    _html =
      render_hook(view, "vote_on_poll", %{
        "poll-id" => poll.id,
        "feed_id" => poll.id,
        "choices" => "0"
      })

    assert render(view) =~ "Vote submitted!"

    _html =
      render_hook(view, "vote_on_poll", %{
        "poll-id" => poll.id,
        "feed_id" => poll.id,
        "choices" => ["1"]
      })

    assert render(view) =~ "You have already voted on this poll."

    {:ok, create} =
      Publish.post_poll(user, "Expired poll", %{
        "options" => ["X", "Y"],
        "expires_in" => 300
      })

    poll = Objects.get_by_ap_id(create.object)
    expired_at = DateTime.add(DateTime.utc_now(), -3600, :second) |> DateTime.to_iso8601()

    {:ok, expired_poll} =
      Objects.update_object(poll, %{data: Map.put(poll.data, "closed", expired_at)})

    _html =
      render_hook(view, "vote_on_poll", %{
        "poll-id" => expired_poll.id,
        "feed_id" => expired_poll.id,
        "choices" => ["0"]
      })

    assert render(view) =~ "This poll has ended."

    conn = Plug.Test.init_test_session(build_conn(), %{user_id: user.id})
    {:ok, owner_view, _html} = live(conn, "/")

    _html =
      render_hook(owner_view, "vote_on_poll", %{
        "poll-id" => expired_poll.id,
        "feed_id" => expired_poll.id,
        "choices" => ["0"]
      })

    assert render(owner_view) =~ "You cannot vote on your own poll."
  end

  test "vote_on_poll handles malformed poll ids without crashing", %{conn: conn} do
    {:ok, bob} = Users.create_local_user("poll_vote_malformed_id_bob")

    conn = Plug.Test.init_test_session(conn, %{user_id: bob.id})
    {:ok, view, _html} = live(conn, "/")

    bad_id = "AAAAAAAAAAAAAAAAA-"

    _html = render_hook(view, "vote_on_poll", %{"poll-id" => bad_id, "choices" => ["0"]})
    assert render(view) =~ "Could not submit vote."
  end

  test "vote_on_poll without choices handles unauth and invalid ids", %{conn: conn, user: user} do
    {:ok, guest_view, _html} = live(conn, "/")

    _html = render_hook(guest_view, "vote_on_poll", %{"poll-id" => "anything"})
    assert render(guest_view) =~ "Register to vote on polls."

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    _html = render_hook(view, "vote_on_poll", %{"poll-id" => "not-a-flake"})
    assert render(view) =~ "Could not submit vote."
  end

  test "delete_post handles unauth and missing posts", %{conn: conn, user: user} do
    {:ok, guest_view, _html} = live(conn, "/")

    _html = render_click(guest_view, "delete_post", %{"id" => FlakeId.get()})
    assert render(guest_view) =~ "Register to delete posts."

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    _html = render_click(view, "delete_post", %{"id" => FlakeId.get()})
    assert render(view) =~ "Could not delete post."
  end

  test "create_post is rejected when signed out", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert Objects.list_notes() == []

    _html = render_click(view, "create_post", %{"post" => %{"content" => "Hello"}})

    assert Objects.list_notes() == []
    assert :sys.get_state(view.pid).socket.assigns.error == "Register to post."
  end

  test "posting an empty post shows an error", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    assert Objects.list_notes() == []

    view
    |> form("#timeline-form", post: %{content: ""})
    |> render_submit()

    assert Objects.list_notes() == []
    assert has_element?(view, "[data-role='compose-error']", "Post can't be empty.")
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

  test "timeline compose panel uses client-side state (no backend open/close events)", %{
    conn: conn,
    user: user
  } do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#compose-panel[phx-hook='ComposePanel']")

    html = render(view)

    refute html =~ "open_compose"
    refute html =~ "close_compose"
    refute html =~ "toggle_compose_cw"
    refute html =~ "toggle_reply_cw"
  end

  test "mention_search and mention_clear manage mention suggestions", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    _html = render_hook(view, "mention_search", %{"q" => "", "scope" => "compose"})

    assert :sys.get_state(view.pid).socket.assigns.mention_suggestions == %{"compose" => []}

    _html = render_hook(view, "mention_clear", %{"scope" => "compose"})
    assert :sys.get_state(view.pid).socket.assigns.mention_suggestions == %{}
  end

  test "timeline does not keep a dead toggle_compose_cw server handler" do
    source = File.read!("lib/egregoros_web/live/timeline_live.ex")
    refute source =~ "toggle_compose_cw"
  end

  test "timeline includes a scroll restore hook for returning from threads", %{
    conn: conn,
    user: user
  } do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#timeline-scroll-restore[phx-hook='ScrollRestore']")
  end

  test "status permalinks include back_timeline so threads can return to the right feed", %{
    conn: conn,
    user: user
  } do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Permalink"), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/?timeline=public")

    assert has_element?(
             view,
             "#post-#{note.id} a[data-role='post-permalink'][href*='back_timeline=public']"
           )
  end

  test "public timeline does not include direct messages", %{conn: conn, user: user} do
    {:ok, _} = Publish.post_note(user, "Hello public")
    {:ok, _} = Publish.post_note(user, "Secret DM", visibility: "direct")

    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "article", "Hello public")
    refute has_element?(view, "article", "Secret DM")
  end

  test "signed-out users see toast feedback for interactions", %{conn: conn, user: user} do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Interactable"), local: true)

    {:ok, view, _html} = live(conn, "/")
    assert has_element?(view, "#post-#{note.id}")

    _html = render_click(view, "toggle_like", %{"id" => note.id})
    assert render(view) =~ "Register to like posts."

    _html = render_click(view, "toggle_repost", %{"id" => note.id})
    assert render(view) =~ "Register to repost."

    _html = render_click(view, "toggle_reaction", %{"id" => note.id, "emoji" => "🔥"})
    assert render(view) =~ "Register to react."

    _html = render_click(view, "toggle_bookmark", %{"id" => note.id})
    assert render(view) =~ "Register to bookmark posts."

    _html =
      render_click(view, "create_reply", %{
        "reply" => %{
          "in_reply_to" => note.ap_id,
          "content" => "Hello"
        }
      })

    assert render(view) =~ "Register to reply."
  end

  test "voting on a boosted poll refreshes the boosted timeline entry", %{conn: conn} do
    {:ok, poll_owner} = Users.create_local_user("poll_owner")
    {:ok, booster} = Users.create_local_user("poll_booster")
    {:ok, voter} = Users.create_local_user("poll_voter")

    assert {:ok, _follow} =
             Relationships.upsert_relationship(%{
               type: "Follow",
               actor: voter.ap_id,
               object: booster.ap_id
             })

    question = %{
      "id" => EgregorosWeb.Endpoint.url() <> "/objects/" <> Ecto.UUID.generate(),
      "type" => "Question",
      "attributedTo" => poll_owner.ap_id,
      "context" => EgregorosWeb.Endpoint.url() <> "/contexts/" <> Ecto.UUID.generate(),
      "to" => ["https://www.w3.org/ns/activitystreams#Public"],
      "content" => "Boosted poll",
      "published" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "oneOf" => [
        %{
          "name" => "Option A",
          "type" => "Note",
          "replies" => %{"type" => "Collection", "totalItems" => 0}
        },
        %{
          "name" => "Option B",
          "type" => "Note",
          "replies" => %{"type" => "Collection", "totalItems" => 0}
        }
      ],
      "closed" => "2030-12-31T23:59:59Z"
    }

    assert {:ok, poll} = Pipeline.ingest(question, local: true)
    assert {:ok, announce} = Pipeline.ingest(Announce.build(booster, poll), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: voter.id})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#post-#{announce.id} form#poll-form-post-#{announce.id}")

    view
    |> form("#poll-form-post-#{announce.id}", %{"choices" => ["0"]})
    |> render_submit()

    assert has_element?(view, "#post-#{announce.id} [data-role='poll-results']")
    refute has_element?(view, "#post-#{announce.id} form#poll-form-post-#{announce.id}")
    refute has_element?(view, "#post-#{poll.id}")
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

  test "home timeline streams direct messages addressed via bto/bcc/audience", %{conn: conn} do
    {:ok, bob} = Users.create_local_user("bob")

    conn = Plug.Test.init_test_session(conn, %{user_id: bob.id})
    {:ok, view, _html} = live(conn, "/")

    refute has_element?(view, "article", "bcc-secret")

    note = %{
      "id" => "https://remote.example/objects/dm-bcc-live",
      "type" => "Note",
      "attributedTo" => "https://remote.example/users/stranger",
      "to" => [],
      "cc" => [],
      "bcc" => [bob.ap_id],
      "content" => "<p>bcc-secret</p>"
    }

    assert {:ok, _object} = Pipeline.ingest(note, local: false)

    assert has_element?(view, "article", "bcc-secret")
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

  test "timeline replaces placeholder actor cards when remote user data arrives", %{conn: conn} do
    actor_ap_id = "https://remote.example/users/bob"

    assert {:ok, note} =
             Pipeline.ingest(
               %{
                 "id" => "https://remote.example/objects/placeholder-actor",
                 "type" => "Note",
                 "actor" => actor_ap_id,
                 "content" => "Hello from bob",
                 "to" => ["https://www.w3.org/ns/activitystreams#Public"],
                 "cc" => []
               },
               local: false
             )

    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#post-#{note.id} [data-role='post-actor-name']", "bob")

    assert {:ok, _user} =
             Users.create_user(%{
               nickname: "bob",
               ap_id: actor_ap_id,
               inbox: actor_ap_id <> "/inbox",
               outbox: actor_ap_id <> "/outbox",
               public_key: "remote-key",
               private_key: nil,
               local: false,
               name: "Bobby",
               avatar_url: "https://remote.example/media/avatar.png"
             })

    assert :ok = Egregoros.UserEvents.broadcast_update(actor_ap_id)
    _ = :sys.get_state(view.pid)

    assert has_element?(view, "#post-#{note.id} [data-role='post-actor-name']", "Bobby")
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

  test "compose dropdown menus declare placement defaults for viewport flipping", %{
    conn: conn,
    user: user
  } do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "[data-role='compose-visibility-menu'][data-placement='bottom']")
    assert has_element?(view, "[data-role='compose-language-menu'][data-placement='bottom']")
    assert has_element?(view, "[data-role='compose-emoji-menu'][data-placement='bottom']")
  end

  test "timeline includes loading skeleton placeholders for infinite scroll", %{
    conn: conn,
    user: user
  } do
    Enum.each(1..21, fn i ->
      assert {:ok, _note} = Pipeline.ingest(Note.build(user, "Scroll post #{i}"), local: true)
    end)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "[data-role='timeline-loading-more']")

    assert has_element?(
             view,
             "[data-role='timeline-loading-more'] [data-role='skeleton-status-card']"
           )
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

  test "for you timeline recommends posts liked by similar accounts", %{conn: conn, user: user} do
    {:ok, bob} = Users.create_local_user("bob")
    {:ok, carol} = Users.create_local_user("carol")
    {:ok, dave} = Users.create_local_user("dave")
    {:ok, eve} = Users.create_local_user("eve")

    assert {:ok, note_1} = Pipeline.ingest(Note.build(bob, "A"), local: true)
    assert {:ok, note_2} = Pipeline.ingest(Note.build(carol, "B"), local: true)
    assert {:ok, note_3} = Pipeline.ingest(Note.build(dave, "C"), local: true)

    assert {:ok, _} = Pipeline.ingest(Like.build(user, note_1), local: true)
    assert {:ok, _} = Pipeline.ingest(Like.build(user, note_2), local: true)

    assert {:ok, _} = Pipeline.ingest(Like.build(eve, note_1), local: true)
    assert {:ok, _} = Pipeline.ingest(Like.build(eve, note_2), local: true)
    assert {:ok, _} = Pipeline.ingest(Like.build(eve, note_3), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/?timeline=for_you")

    assert has_element?(view, "[data-role='timeline-current']", "for_you")
    assert has_element?(view, "#post-#{note_3.id}")
    refute has_element?(view, "#post-#{note_1.id}")
    refute has_element?(view, "#post-#{note_2.id}")
  end

  test "local timeline shows only local public posts", %{conn: conn, user: user} do
    assert {:ok, _local_note} = Pipeline.ingest(Note.build(user, "Local note"), local: true)

    assert {:ok, _remote_note} =
             Pipeline.ingest(
               %{
                 "id" => "https://remote.example/objects/remote-local-timeline",
                 "type" => "Note",
                 "attributedTo" => "https://remote.example/users/bob",
                 "to" => ["https://www.w3.org/ns/activitystreams#Public"],
                 "cc" => ["https://remote.example/users/bob/followers"],
                 "content" => "<p>Remote note</p>"
               },
               local: false
             )

    {:ok, view, _html} = live(conn, "/?timeline=local")

    assert has_element?(view, "[data-role='timeline-current']", "local")
    assert has_element?(view, "article[data-role='status-card']", "Local note")
    refute has_element?(view, "article[data-role='status-card']", "Remote note")
  end

  test "compose sheet is controlled by client-side events", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#compose-overlay[data-state='closed']")
    assert render(view) =~ "egregoros:compose-open"
    assert render(view) =~ "egregoros:compose-close"
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
    assert html =~ note.ap_id
    refute html =~ "open_reply_modal"
    refute html =~ "?reply=true"
  end

  test "reply buttons embed mention handles for frontend prefill", %{conn: conn, user: user} do
    {:ok, bob} = Users.create_local_user("bob")
    {:ok, _carol} = Users.create_local_user("carol")

    assert {:ok, _create} = Publish.post_note(bob, "Hi @carol")
    [note] = Objects.list_notes_by_actor(bob.ap_id, limit: 1)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/?timeline=public")

    html =
      view
      |> element("#post-#{note.id} button[data-role='reply']")
      |> render()

    assert html =~ "mention_handles"
    assert html =~ "@carol"
  end

  test "reply button mention handles include remote domains", %{conn: conn, user: user} do
    assert {:ok, note} =
             Pipeline.ingest(
               %{
                 "id" => "https://shitposter.world/objects/mention-domain",
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

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/?timeline=public")

    html =
      view
      |> element("#post-#{note.id} button[data-role='reply']")
      |> render()

    assert html =~ "mention_handles"
    assert html =~ "@nerthos@shitposter.world"
    assert html =~ "@noyoushutthefuckupdad@shitposter.world"
  end

  test "reply buttons ignore invalid mention tags in frontend prefill data", %{
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
                 "content" => "<p>hi</p>",
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
    {:ok, view, _html} = live(conn, "/?timeline=public")

    html =
      view
      |> element("#post-#{note.id} button[data-role='reply']")
      |> render()

    refute html =~ "@-bad"
  end

  test "reply modal controls are client-side and carry reply target data", %{
    conn: conn,
    user: user
  } do
    assert {:ok, parent} = Pipeline.ingest(Note.build(user, "Reply target"), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#reply-modal[data-role='reply-modal'][data-state='closed']")
    assert has_element?(view, "input[data-role='reply-in-reply-to'][value='']")

    reply_html =
      view
      |> element("#post-#{parent.id} button[data-role='reply']")
      |> render()

    assert reply_html =~ "egregoros:reply-open"
    assert reply_html =~ parent.ap_id
    assert reply_html =~ "@alice"
    refute reply_html =~ "open_reply_modal"

    close_html =
      view
      |> element("#reply-modal [data-role='reply-modal-close']")
      |> render()

    assert close_html =~ "egregoros:reply-close"
    refute close_html =~ "close_reply_modal"
  end

  test "reply_change opens the content warning area when spoiler_text is present", %{
    conn: conn,
    user: user
  } do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    refute has_element?(view, "#reply-modal [data-role='compose-cw'][data-state='open']")

    _html = render_change(view, "reply_change", %{"reply" => %{"spoiler_text" => "cw"}})

    assert has_element?(view, "#reply-modal [data-role='compose-cw'][data-state='open']")
  end

  test "create_reply is rejected when signed out", %{conn: conn, user: user} do
    assert {:ok, parent} = Pipeline.ingest(Note.build(user, "Reply target"), local: true)

    {:ok, view, _html} = live(conn, "/")

    _html =
      render_click(view, "create_reply", %{
        "reply" => %{
          "in_reply_to" => parent.ap_id,
          "content" => "Hello"
        }
      })

    assert render(view) =~ "Register to reply."
    assert Objects.list_replies_to(parent.ap_id, limit: 1) == []
  end

  test "create_reply falls back to the in_reply_to param when no modal target is set", %{
    conn: conn,
    user: user
  } do
    assert {:ok, parent} = Pipeline.ingest(Note.build(user, "Reply target"), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    _html =
      render_click(view, "create_reply", %{
        "reply" => %{
          "in_reply_to" => parent.ap_id,
          "content" => "Hello"
        }
      })

    [reply] = Objects.list_replies_to(parent.ap_id, limit: 1)
    assert reply.data["inReplyTo"] == parent.ap_id
  end

  test "cancel_reply_media removes uploads from the reply composer", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

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
    html = render(view)
    assert [_, ref] = Regex.run(~r/id="reply-modal-media-entry-([^"]+)"/, html)

    assert has_element?(view, "#reply-modal-media-entry-#{ref}")

    view
    |> element("#reply-modal-media-entry-#{ref} button[aria-label='Remove attachment']")
    |> render_click()

    refute has_element?(view, "#reply-modal-media-entry-#{ref}")
  end

  test "replying with an attachment creates a reply with attachments", %{conn: conn, user: user} do
    assert {:ok, parent} = Pipeline.ingest(Note.build(user, "Reply target"), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

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

    _html =
      render_click(view, "create_reply", %{
        "reply" => %{
          "in_reply_to" => parent.ap_id,
          "content" => "Hello"
        }
      })

    [reply] = Objects.list_replies_to(parent.ap_id, limit: 1)
    assert reply.data["inReplyTo"] == parent.ap_id
    assert length(List.wrap(reply.data["attachment"])) == 1
  end

  test "signed-in users can reply from the timeline", %{conn: conn, user: user} do
    assert {:ok, parent} = Pipeline.ingest(Note.build(user, "Parent post"), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    view
    |> form("#reply-modal-form", reply: %{in_reply_to: parent.ap_id, content: "A reply"})
    |> render_submit()

    [reply] = Objects.list_replies_to(parent.ap_id, limit: 1)
    assert reply.data["inReplyTo"] == parent.ap_id
  end

  test "replying shows errors for empty and too-long replies", %{conn: conn, user: user} do
    assert {:ok, parent} = Pipeline.ingest(Note.build(user, "Reply target"), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    view
    |> form("#reply-modal-form", reply: %{in_reply_to: parent.ap_id, content: ""})
    |> render_submit()

    html = render(view)
    assert html =~ "Reply can"
    assert html =~ "be empty."
    assert Objects.list_replies_to(parent.ap_id, limit: 1) == []

    long_content = String.duplicate("a", 5001)

    view
    |> form("#reply-modal-form", reply: %{in_reply_to: parent.ap_id, content: long_content})
    |> render_submit()

    assert render(view) =~ "Reply is too long."
    assert Objects.list_replies_to(parent.ap_id, limit: 1) == []
  end

  test "create_reply respects ui_cw_open param for error state", %{conn: conn, user: user} do
    assert {:ok, parent} = Pipeline.ingest(Note.build(user, "Reply target"), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    _html =
      render_click(view, "create_reply", %{
        "reply" => %{
          "in_reply_to" => parent.ap_id,
          "content" => "",
          "ui_cw_open" => "true"
        }
      })

    assert :sys.get_state(view.pid).socket.assigns.reply_cw_open?
    assert render(view) =~ "Reply can"
    assert render(view) =~ "be empty."
  end

  test "timeline marks end when there are no more posts", %{conn: conn, user: user} do
    for idx <- 1..10 do
      assert {:ok, _} = Pipeline.ingest(Note.build(user, "Post #{idx}"), local: true)
    end

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/?timeline=public")

    assert has_element?(view, "[data-role='load-more']")

    _html = render_click(view, "load_more", %{})

    refute has_element?(view, "[data-role='load-more']")
    assert :sys.get_state(view.pid).socket.assigns.posts_end?
  end

  test "for_you falls back to public when signed out", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/?timeline=for_you")

    assert :sys.get_state(view.pid).socket.assigns.timeline == :public
  end

  test "timeline initial fetch renders up to 10 posts", %{conn: conn, user: user} do
    for idx <- 1..25 do
      assert {:ok, _} = Pipeline.ingest(Note.build(user, "Post #{idx}"), local: true)
    end

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/?timeline=public")

    html = render(view)

    assert length(Regex.scan(~r/data-role=\"status-card\"/, html)) == 10
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

  test "reaction picker options are rendered client-side", %{conn: conn, user: user} do
    assert {:ok, _} = Pipeline.ingest(Note.build(user, "Reactable"), local: true)
    [note] = Objects.list_notes()

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/?timeline=public")

    assert has_element?(view, "#post-#{note.id} [data-role='reaction-picker']")
    refute has_element?(view, "#post-#{note.id} [data-role='reaction-picker-option']")
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

  test "sharing a badge from the timeline shows a toast message", %{conn: conn, user: user} do
    {:ok, issuer} = Users.create_local_user("badge_issuer")

    credential =
      Fixtures.json!("openbadge_vc.json")
      |> Map.put("issuer", issuer.ap_id)
      |> Map.put("to", ["https://www.w3.org/ns/activitystreams#Public"])
      |> put_in(["credentialSubject", "id"], user.ap_id)

    assert {:ok, credential_object} = Pipeline.ingest(credential, local: true)

    assert {:ok, announce} =
             Pipeline.ingest(Announce.build(issuer, credential_object), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/?timeline=public")

    assert has_element?(view, "#post-#{announce.id} button[data-role='repost']")

    view
    |> element("#post-#{announce.id} button[data-role='repost']")
    |> render_click()

    assert has_element?(view, "[data-role='toast']", "Badge shared.")
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

  test "custom emoji reactions render as images and stream into the timeline", %{
    conn: conn,
    user: user
  } do
    {:ok, note} = Pipeline.ingest(Note.build(user, "Hello world"), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    refute has_element?(
             view,
             "#post-#{note.id} button[data-role='reaction'][data-emoji='flow_think']"
           )

    activity = %{
      "id" => "https://remote.example/users/bob#reactions/1",
      "type" => "EmojiReact",
      "actor" => "https://remote.example/users/bob",
      "object" => note.ap_id,
      "content" => ":flow_think:",
      "tag" => [
        %{
          "type" => "Emoji",
          "name" => "flow_think",
          "icon" => %{"type" => "Image", "url" => "https://remote.example/emoji/flow_think.png"}
        }
      ]
    }

    assert {:ok, _react} = Pipeline.ingest(activity, local: false)
    _ = :sys.get_state(view.pid)

    assert has_element?(
             view,
             "#post-#{note.id} button[data-role='reaction'][data-emoji='flow_think']",
             "1"
           )

    assert has_element?(
             view,
             "#post-#{note.id} button[data-role='reaction'][data-emoji='flow_think'] img.emoji[alt=':flow_think:']"
           )
  end

  test "interaction buttons dispatch optimistic toggle events", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    view
    |> form("#timeline-form", post: %{content: "Hello world"})
    |> render_submit()

    [note] = Objects.list_notes()

    like_html =
      view
      |> element("#post-#{note.id} button[data-role='like']")
      |> render()

    assert like_html =~ "egregoros:optimistic-toggle"

    repost_html =
      view
      |> element("#post-#{note.id} button[data-role='repost']")
      |> render()

    assert repost_html =~ "egregoros:optimistic-toggle"

    reaction_html =
      view
      |> element("#post-#{note.id} button[data-role='reaction'][data-emoji='🔥']")
      |> render()

    assert reaction_html =~ "egregoros:optimistic-toggle"
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

  test "image attachments render with thumbnail previews in the timeline", %{
    conn: conn,
    user: user
  } do
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

    html =
      view
      |> element("#post-#{note.id} img[data-role='attachment'][data-kind='image']")
      |> render()

    full = EgregorosWeb.Endpoint.url() <> "/uploads/media/#{user.id}/photo.png"
    thumb = EgregorosWeb.Endpoint.url() <> "/uploads/media/#{user.id}/photo-thumb.jpg"

    assert html =~ "data-full-href=\"#{full}\""
    assert html =~ "src=\"#{thumb}\""
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

  test "video attachments render a player without a fullscreen button", %{conn: conn} do
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

    assert has_element?(
             view,
             "#post-#{note.id} [phx-hook='VideoPlayer'][phx-update='ignore']"
           )

    refute has_element?(
             view,
             "#post-#{note.id} button[data-role='attachment-open'][data-index='0']"
           )
  end

  test "audio attachments render a player without a fullscreen button", %{conn: conn} do
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

    refute has_element?(
             view,
             "#post-#{note.id} button[data-role='attachment-open'][data-index='0']"
           )
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

  test "media viewer hides navigation controls when closed with no selected media", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/?timeline=public")

    assert has_element?(view, "#media-viewer[data-role='media-viewer'][data-state='closed']")
    assert has_element?(view, "#media-viewer button[data-role='media-viewer-prev'][hidden]")
    assert has_element?(view, "#media-viewer button[data-role='media-viewer-next'][hidden]")
  end

  test "timeline can be switched between home and public via patch", %{conn: conn, user: user} do
    assert {:ok, _public_post} = Pipeline.ingest(Note.build(user, "Public post"), local: true)

    assert {:ok, _dm_post} =
             Pipeline.ingest(
               %{
                 "id" => "https://remote.example/objects/dm-for-switch",
                 "type" => "Note",
                 "attributedTo" => "https://remote.example/users/stranger",
                 "to" => [user.ap_id],
                 "cc" => [],
                 "content" => "<p>Switch DM</p>"
               },
               local: false
             )

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/?timeline=home")

    assert has_element?(view, "[data-role='timeline-current']", "home")
    assert has_element?(view, "article[data-role='status-card']", "Switch DM")

    view
    |> element("a", "Public")
    |> render_click()

    assert_patch(view, "/?timeline=public")
    assert has_element?(view, "[data-role='timeline-current']", "public")
    refute has_element?(view, "article[data-role='status-card']", "Switch DM")
  end

  test "compose content warning can be toggled and cleared", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#compose-cw[data-role='compose-cw'][data-state='closed']")

    _html =
      render_change(view, "compose_change", %{
        "post" => %{"ui_cw_open" => "true"}
      })

    assert has_element?(view, "#compose-cw[data-role='compose-cw'][data-state='open']")

    _html =
      render_change(view, "compose_change", %{
        "post" => %{"ui_cw_open" => "true", "spoiler_text" => "CW", "content" => "hello"}
      })

    assert has_element?(view, "input[name='post[spoiler_text]'][value='CW']")

    _html =
      render_change(view, "compose_change", %{
        "post" => %{
          "ui_cw_open" => "false",
          "spoiler_text" => "",
          "content" => "hello"
        }
      })

    assert has_element?(view, "#compose-cw[data-role='compose-cw'][data-state='closed']")
    assert has_element?(view, "input[name='post[spoiler_text]'][value='']")
  end

  test "timeline shows feedback when copying a post link", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    _html = render_click(view, "copied_link", %{})

    assert render(view) =~ "Copied link to clipboard."
  end

  test "attachments can be removed from the composer", %{conn: conn, user: user} do
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

    assert render_upload(upload, "photo.png") =~ "100%"
    assert has_element?(view, "[data-role='media-entry']")

    view
    |> element("[data-role='media-entry'] button[phx-click='cancel_media']")
    |> render_click()

    refute has_element?(view, "[data-role='media-entry']")
  end

  test "composer renders attachment previews in a grid", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    fixture_path = Fixtures.path!("DSCN0010.png")
    content = File.read!(fixture_path)

    upload =
      file_input(view, "#timeline-form", :media, [
        %{
          last_modified: 1_694_171_879_000,
          name: "first.png",
          content: content,
          size: byte_size(content),
          type: "image/png"
        },
        %{
          last_modified: 1_694_171_879_001,
          name: "second.png",
          content: content,
          size: byte_size(content),
          type: "image/png"
        }
      ])

    assert render_upload(upload, "first.png") =~ "100%"
    assert render_upload(upload, "second.png") =~ "100%"

    assert has_element?(view, "[data-role='compose-media-grid']")

    html = render(view)
    assert length(Regex.scan(~r/data-role=\"media-entry\"/, html)) == 2
  end

  test "posting reports upload failures from the media storage backend", %{conn: conn, user: user} do
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
          type: "image/png"
        }
      ])

    expect(Egregoros.MediaStorage.Mock, :store_media, fn passed_user, _upload ->
      assert passed_user.id == user.id
      {:error, :storage_failed}
    end)

    assert render_upload(upload, "photo.png") =~ "100%"

    view
    |> form("#timeline-form", post: %{content: "Hello with failing media"})
    |> render_submit()

    assert has_element?(view, "[data-role='compose-error']", "Could not upload attachment.")
  end

  test "home timeline includes direct messages addressed via recipient map ids", %{
    conn: conn,
    user: user
  } do
    dm_1 = %{
      "id" => "https://remote.example/objects/dm-map-1",
      "type" => "Note",
      "attributedTo" => "https://remote.example/users/stranger",
      "to" => [%{"id" => user.ap_id}],
      "cc" => [],
      "content" => "<p>dm-map-1</p>"
    }

    dm_2 = %{
      "id" => "https://remote.example/objects/dm-map-2",
      "type" => "Note",
      "attributedTo" => "https://remote.example/users/stranger",
      "to" => [%{id: user.ap_id}],
      "cc" => [],
      "content" => "<p>dm-map-2</p>"
    }

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    refute has_element?(view, "article[data-role='status-card']", "dm-map-1")
    refute has_element?(view, "article[data-role='status-card']", "dm-map-2")

    assert {:ok, _} = Pipeline.ingest(dm_1, local: false)
    assert {:ok, _} = Pipeline.ingest(dm_2, local: false)
    _ = :sys.get_state(view.pid)

    assert has_element?(view, "article[data-role='status-card']", "dm-map-1")
    assert has_element?(view, "article[data-role='status-card']", "dm-map-2")
  end

  test "reply composer state reacts to cw toggles and reply_change events", %{
    conn: conn,
    user: user
  } do
    assert {:ok, _parent} = Pipeline.ingest(Note.build(user, "Reply target"), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#reply-modal[data-role='reply-modal'][data-state='closed']")
    assert has_element?(view, "#reply-modal-cw[data-role='compose-cw'][data-state='closed']")

    _html =
      render_change(view, "reply_change", %{
        "reply" => %{"ui_cw_open" => "true"}
      })

    assert has_element?(view, "#reply-modal-cw[data-role='compose-cw'][data-state='open']")

    _html =
      render_change(view, "reply_change", %{
        "reply" => %{"ui_options_open" => "true", "spoiler_text" => "cw"}
      })

    assert has_element?(
             view,
             "input[type='hidden'][data-role='compose-options-state'][name='reply[ui_options_open]'][value='true']"
           )
  end

  test "replying reports upload failures from the media storage backend", %{
    conn: conn,
    user: user
  } do
    assert {:ok, parent} = Pipeline.ingest(Note.build(user, "Reply target"), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

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

    expect(Egregoros.MediaStorage.Mock, :store_media, fn passed_user, _upload ->
      assert passed_user.id == user.id
      {:error, :storage_failed}
    end)

    assert render_upload(upload, "photo.png") =~ "100%"

    view
    |> form("#reply-modal-form",
      reply: %{in_reply_to: parent.ap_id, content: "Reply with failing media"}
    )
    |> render_submit()

    assert render(view) =~ "Could not upload attachment."
  end

  test "new posts label pluralizes when multiple posts are buffered", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    render_hook(view, "timeline_at_top", %{"at_top" => false})

    assert {:ok, _} = Pipeline.ingest(Note.build(user, "Buffered 1"), local: true)
    assert {:ok, _} = Pipeline.ingest(Note.build(user, "Buffered 2"), local: true)
    _ = :sys.get_state(view.pid)

    assert has_element?(view, "button[data-role='new-posts']", "2 new posts")
  end

  test "home timeline shows announces from followed users", %{conn: conn, user: alice} do
    {:ok, bob} = Users.create_local_user("bob")
    {:ok, charlie} = Users.create_local_user("charlie")

    assert {:ok, _follow} = Pipeline.ingest(Follow.build(bob, alice), local: true)
    assert {:ok, note} = Pipeline.ingest(Note.build(charlie, "Boost me"), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: bob.id})
    {:ok, view, _html} = live(conn, "/")

    refute has_element?(view, "article", "Boost me")

    assert {:ok, announce} = Pipeline.ingest(Announce.build(alice, note), local: true)

    assert has_element?(view, "#post-#{announce.id}")
    assert has_element?(view, "#post-#{announce.id}", "Boost me")
    assert has_element?(view, "#post-#{announce.id} [data-role='reposted-by']", "alice")
    assert has_element?(view, "#post-#{announce.id} [data-role='reposted-by']", "reposted")
    assert has_element?(view, "#post-#{announce.id} [data-role='post-actor-handle']", "@charlie")
  end

  test "liking a boosted post updates the boost entry instead of inserting a duplicate note", %{
    conn: conn,
    user: alice
  } do
    {:ok, bob} = Users.create_local_user("bob")
    {:ok, charlie} = Users.create_local_user("charlie")

    assert {:ok, _follow} = Pipeline.ingest(Follow.build(bob, alice), local: true)
    assert {:ok, note} = Pipeline.ingest(Note.build(charlie, "Boost target"), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: bob.id})
    {:ok, view, _html} = live(conn, "/")

    assert {:ok, announce} = Pipeline.ingest(Announce.build(alice, note), local: true)
    assert has_element?(view, "#post-#{announce.id}")

    view
    |> element("#post-#{announce.id} button[data-role='like']")
    |> render_click()

    assert has_element?(
             view,
             "#post-#{announce.id} button[data-role='like'][aria-pressed='true']"
           )

    refute has_element?(view, "#post-#{note.id}")
  end
end
