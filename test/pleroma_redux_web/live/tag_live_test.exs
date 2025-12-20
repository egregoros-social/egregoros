defmodule PleromaReduxWeb.TagLiveTest do
  use PleromaReduxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PleromaRedux.Activities.Note
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Users

  setup do
    {:ok, user} = Users.create_local_user("alice")

    assert {:ok, _note} = Pipeline.ingest(Note.build(user, "Hello #elixir"), local: true)

    %{user: user}
  end

  test "tag pages list matching posts", %{conn: conn} do
    assert {:ok, view, _html} = live(conn, "/tags/elixir")

    assert has_element?(view, "[data-role='tag-title']", "#elixir")
    assert has_element?(view, "article", "Hello #elixir")
  end
end

