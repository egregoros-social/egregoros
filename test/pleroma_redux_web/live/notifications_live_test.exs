defmodule PleromaReduxWeb.NotificationsLiveTest do
  use PleromaReduxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PleromaRedux.Activities.Follow
  alias PleromaRedux.Notifications
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Users

  setup do
    {:ok, user} = Users.create_local_user("alice")
    {:ok, actor} = Users.create_local_user("bob")

    %{user: user, actor: actor}
  end

  test "renders notifications for a signed-in user", %{conn: conn, user: user, actor: actor} do
    assert {:ok, _} = Pipeline.ingest(Follow.build(actor, user), local: true)
    [notification] = Notifications.list_for_user(user, limit: 1)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/notifications")

    assert has_element?(view, "#notification-#{notification.id}")
    assert has_element?(view, "[data-role='notification'][data-type='Follow']")
  end

  test "notifications can load more items", %{conn: conn, user: user, actor: actor} do
    for idx <- 1..25 do
      assert {:ok, _} =
               Pipeline.ingest(
                 %{
                   "id" => "http://localhost:4000/activities/follow/#{idx}",
                   "type" => "Follow",
                   "actor" => actor.ap_id,
                   "object" => user.ap_id
                 },
                 local: true
               )
    end

    notifications = Notifications.list_for_user(user, limit: 25)
    oldest = List.last(notifications)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/notifications")

    refute has_element?(view, "#notification-#{oldest.id}")

    view
    |> element("button[data-role='notifications-load-more']")
    |> render_click()

    assert has_element?(view, "#notification-#{oldest.id}")
  end

  test "streams new notifications into the list", %{conn: conn, user: user, actor: actor} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/notifications")

    assert {:ok, activity} = Pipeline.ingest(Follow.build(actor, user), local: true)

    send(view.pid, {:notification_created, activity})
    _ = :sys.get_state(view.pid)

    assert has_element?(view, "#notification-#{activity.id}")
  end
end
