defmodule PleromaReduxWeb.BookmarksLiveTest do
  use PleromaReduxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PleromaRedux.Activities.Note
  alias PleromaRedux.Interactions
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Users

  setup do
    {:ok, user} = Users.create_local_user("alice")
    %{user: user}
  end

  test "bookmarks page shows bookmarked posts and allows unbookmarking", %{conn: conn, user: user} do
    {:ok, note} = Pipeline.ingest(Note.build(user, "Hello bookmarked"), local: true)
    assert {:ok, :bookmarked} = Interactions.toggle_bookmark(user, note.id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/bookmarks")

    assert has_element?(view, "#post-#{note.id}", "Hello bookmarked")
    assert has_element?(view, "#post-#{note.id} button[data-role='bookmark']", "Unbookmark")

    view
    |> element("#post-#{note.id} button[data-role='bookmark']")
    |> render_click()

    refute has_element?(view, "#post-#{note.id}")
  end
end
