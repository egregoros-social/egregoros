defmodule EgregorosWeb.MastodonAPI.FollowRequestsControllerTest do
  use EgregorosWeb.ConnCase, async: true

  import Mox

  alias Egregoros.Activities.Follow
  alias Egregoros.Pipeline
  alias Egregoros.Relationships
  alias Egregoros.Users

  setup do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")
    {:ok, alice} = Users.update_profile(alice, %{locked: true})

    %{alice: alice, bob: bob}
  end

  test "GET /api/v1/follow_requests lists pending follow requests", %{
    conn: conn,
    alice: alice,
    bob: bob
  } do
    assert {:ok, _follow_object} = Pipeline.ingest(Follow.build(bob, alice), local: true)

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, alice} end)

    conn = get(conn, "/api/v1/follow_requests")
    response = json_response(conn, 200)

    assert length(response) == 1
    assert hd(response)["id"] == Integer.to_string(bob.id)
  end

  test "POST /api/v1/follow_requests/:id/authorize accepts request", %{
    conn: conn,
    alice: alice,
    bob: bob
  } do
    assert {:ok, _follow_object} = Pipeline.ingest(Follow.build(bob, alice), local: true)

    assert Relationships.get_by_type_actor_object("FollowRequest", bob.ap_id, alice.ap_id)

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, alice} end)

    conn = post(conn, "/api/v1/follow_requests/#{bob.id}/authorize")
    assert json_response(conn, 200) == %{}

    assert Relationships.get_by_type_actor_object("FollowRequest", bob.ap_id, alice.ap_id) == nil
    assert Relationships.get_by_type_actor_object("Follow", bob.ap_id, alice.ap_id)
  end

  test "POST /api/v1/follow_requests/:id/reject rejects request", %{
    conn: conn,
    alice: alice,
    bob: bob
  } do
    assert {:ok, _follow_object} = Pipeline.ingest(Follow.build(bob, alice), local: true)

    assert Relationships.get_by_type_actor_object("FollowRequest", bob.ap_id, alice.ap_id)

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, alice} end)

    conn = post(conn, "/api/v1/follow_requests/#{bob.id}/reject")
    assert json_response(conn, 200) == %{}

    assert Relationships.get_by_type_actor_object("FollowRequest", bob.ap_id, alice.ap_id) == nil
    assert Relationships.get_by_type_actor_object("Follow", bob.ap_id, alice.ap_id) == nil
  end
end
