defmodule PleromaReduxWeb.ProfileLiveTest do
  use PleromaReduxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PleromaRedux.Activities.Note
  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Relationships
  alias PleromaRedux.Users

  setup do
    {:ok, viewer} = Users.create_local_user("alice")
    {:ok, profile_user} = Users.create_local_user("bob")

    %{viewer: viewer, profile_user: profile_user}
  end

  test "profile supports follow and unfollow", %{
    conn: conn,
    viewer: viewer,
    profile_user: profile_user
  } do
    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{profile_user.nickname}")

    refute Relationships.get_by_type_actor_object("Follow", viewer.ap_id, profile_user.ap_id)

    view
    |> element("button[data-role='profile-follow']")
    |> render_click()

    assert %{} =
             relationship =
             Relationships.get_by_type_actor_object("Follow", viewer.ap_id, profile_user.ap_id)

    assert has_element?(view, "button[data-role='profile-unfollow']")

    view
    |> element("button[data-role='profile-unfollow']")
    |> render_click()

    assert Relationships.get(relationship.id) == nil
    assert has_element?(view, "button[data-role='profile-follow']")
  end

  test "profile can load more posts", %{conn: conn, viewer: viewer, profile_user: profile_user} do
    for idx <- 1..25 do
      assert {:ok, _} = Pipeline.ingest(Note.build(profile_user, "Post #{idx}"), local: true)
    end

    notes = Objects.list_notes_by_actor(profile_user.ap_id, limit: 25)
    oldest = List.last(notes)

    conn = Plug.Test.init_test_session(conn, %{user_id: viewer.id})
    {:ok, view, _html} = live(conn, "/@#{profile_user.nickname}")

    refute has_element?(view, "#post-#{oldest.id}")

    view
    |> element("button[data-role='profile-load-more']")
    |> render_click()

    assert has_element?(view, "#post-#{oldest.id}")
  end
end
