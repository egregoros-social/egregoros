defmodule PleromaReduxWeb.SearchLiveTest do
  use PleromaReduxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PleromaRedux.Users

  test "searching by query lists matching accounts", %{conn: conn} do
    {:ok, _} = Users.create_local_user("alice")
    {:ok, _} = Users.create_local_user("bob")

    {:ok, view, _html} = live(conn, "/search?q=bo")

    assert has_element?(view, "[data-role='search-results']")
    assert has_element?(view, "[data-role='search-result-handle']", "@bob")
    refute has_element?(view, "[data-role='search-result-handle']", "@alice")
  end
end
