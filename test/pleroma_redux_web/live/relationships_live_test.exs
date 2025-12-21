defmodule PleromaReduxWeb.RelationshipsLiveTest do
  use PleromaReduxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PleromaRedux.Activities.Follow
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Relationships
  alias PleromaRedux.Users

  setup do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    assert {:ok, _follow} = Pipeline.ingest(Follow.build(alice, bob), local: true)

    %{alice: alice, bob: bob}
  end

  test "followers page lists followers", %{conn: conn, bob: bob} do
    assert {:ok, view, _html} = live(conn, "/@#{bob.nickname}/followers")

    assert has_element?(view, "[data-role='relationships-title']", "Followers")
    assert has_element?(view, "[data-role='relationship-item']", "@alice")
  end

  test "following page lists followed accounts", %{conn: conn, alice: alice} do
    assert {:ok, view, _html} = live(conn, "/@#{alice.nickname}/following")

    assert has_element?(view, "[data-role='relationships-title']", "Following")
    assert has_element?(view, "[data-role='relationship-item']", "@bob")
  end

  test "followers page can load more followers", %{conn: conn, bob: bob} do
    for idx <- 1..41 do
      nickname = "follower#{idx}"

      {:ok, user} =
        Users.create_user(%{
          nickname: nickname,
          ap_id: "https://remote.example/users/#{nickname}",
          inbox: "https://remote.example/users/#{nickname}/inbox",
          outbox: "https://remote.example/users/#{nickname}/outbox",
          public_key: "public-key",
          local: false
        })

      follow = %{
        "id" => "https://remote.example/activities/follow/#{idx}",
        "type" => "Follow",
        "actor" => user.ap_id,
        "object" => bob.ap_id,
        "to" => [bob.ap_id],
        "published" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      assert {:ok, _follow} = Pipeline.ingest(follow, local: false)
    end

    excluded_relationship =
      bob.ap_id
      |> Relationships.list_follows_to(limit: 80)
      |> Enum.drop(40)
      |> List.first()

    assert excluded_relationship
    excluded_user = Users.get_by_ap_id(excluded_relationship.actor)
    assert excluded_user

    assert {:ok, view, _html} = live(conn, "/@#{bob.nickname}/followers")

    refute has_element?(
             view,
             "[data-role='relationship-item']",
             "@#{excluded_user.nickname}@remote.example"
           )

    view
    |> element("button[data-role='relationships-load-more']")
    |> render_click()

    assert has_element?(
             view,
             "[data-role='relationship-item']",
             "@#{excluded_user.nickname}@remote.example"
           )
  end
end
