defmodule PleromaReduxWeb.TimelineLiveTest do
  use PleromaReduxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

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
end
