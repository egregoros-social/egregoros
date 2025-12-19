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

  test "timeline renders sidebar and feed panels", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#timeline-shell")
    assert has_element?(view, "#timeline-sidebar")
    assert has_element?(view, "#timeline-feed")
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
end
