defmodule PleromaReduxWeb.TagLiveTest do
  use PleromaReduxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PleromaRedux.Activities.Note
  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Users

  setup do
    {:ok, user} = Users.create_local_user("alice")

    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Hello #elixir"), local: true)

    %{user: user, note: note}
  end

  test "tag pages list matching posts", %{conn: conn} do
    assert {:ok, view, _html} = live(conn, "/tags/elixir")

    assert has_element?(view, "[data-role='tag-title']", "#elixir")
    assert has_element?(view, "article", "Hello #elixir")
  end

  test "signed-in users can like posts from tag pages", %{conn: conn, user: user, note: note} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/tags/elixir")

    refute Objects.get_by_type_actor_object("Like", user.ap_id, note.ap_id)

    view
    |> element("#post-#{note.id} button[data-role='like']")
    |> render_click()

    assert Objects.get_by_type_actor_object("Like", user.ap_id, note.ap_id)
    assert has_element?(view, "#post-#{note.id} button[data-role='like']", "Unlike")
  end

  test "signed-in users can repost posts from tag pages", %{conn: conn, user: user, note: note} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/tags/elixir")

    refute Objects.get_by_type_actor_object("Announce", user.ap_id, note.ap_id)

    view
    |> element("#post-#{note.id} button[data-role='repost']")
    |> render_click()

    assert Objects.get_by_type_actor_object("Announce", user.ap_id, note.ap_id)
    assert has_element?(view, "#post-#{note.id} button[data-role='repost']", "Unrepost")
  end

  test "signed-in users can react to posts from tag pages", %{conn: conn, user: user, note: note} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/tags/elixir")

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

  test "tag pages can load more posts", %{conn: conn, user: user} do
    for idx <- 1..25 do
      assert {:ok, _note} = Pipeline.ingest(Note.build(user, "Post #{idx} #elixir"), local: true)
    end

    notes = Objects.list_notes_by_hashtag("elixir", limit: 40)
    oldest = List.last(notes)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/tags/elixir")

    refute has_element?(view, "#post-#{oldest.id}")

    view
    |> element("button[data-role='tag-load-more']")
    |> render_click()

    assert has_element?(view, "#post-#{oldest.id}")
  end
end
