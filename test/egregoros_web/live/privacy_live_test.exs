defmodule EgregorosWeb.PrivacyLiveTest do
  use EgregorosWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Egregoros.Relationships
  alias Egregoros.Users

  setup do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")
    {:ok, carol} = Users.create_local_user("carol")

    {:ok, mute} =
      Relationships.upsert_relationship(%{
        type: "Mute",
        actor: alice.ap_id,
        object: bob.ap_id,
        activity_ap_id: nil
      })

    {:ok, block} =
      Relationships.upsert_relationship(%{
        type: "Block",
        actor: alice.ap_id,
        object: carol.ap_id,
        activity_ap_id: nil
      })

    %{alice: alice, bob: bob, carol: carol, mute: mute, block: block}
  end

  test "lists blocks and mutes for the current user", %{
    conn: conn,
    alice: alice,
    mute: mute,
    block: block
  } do
    conn = Plug.Test.init_test_session(conn, %{user_id: alice.id})
    {:ok, view, _html} = live(conn, "/settings/privacy")

    assert has_element?(view, "#mute-#{mute.id}")
    assert has_element?(view, "#mute-#{mute.id} [data-role='privacy-target-handle']", "@bob")
    assert has_element?(view, "#block-#{block.id}")
    assert has_element?(view, "#block-#{block.id} [data-role='privacy-target-handle']", "@carol")
  end

  test "mutes can be removed from the privacy screen", %{conn: conn, alice: alice, mute: mute} do
    conn = Plug.Test.init_test_session(conn, %{user_id: alice.id})
    {:ok, view, _html} = live(conn, "/settings/privacy")

    assert has_element?(view, "#mute-#{mute.id}")

    view
    |> element("button[data-role='privacy-unmute'][phx-value-id='#{mute.id}']")
    |> render_click()

    assert Relationships.get(mute.id) == nil
    refute has_element?(view, "#mute-#{mute.id}")
  end

  test "blocks can be removed from the privacy screen", %{conn: conn, alice: alice, block: block} do
    conn = Plug.Test.init_test_session(conn, %{user_id: alice.id})
    {:ok, view, _html} = live(conn, "/settings/privacy")

    assert has_element?(view, "#block-#{block.id}")

    view
    |> element("button[data-role='privacy-unblock'][phx-value-id='#{block.id}']")
    |> render_click()

    assert Relationships.get(block.id) == nil
    refute has_element?(view, "#block-#{block.id}")
  end

  test "signed-out users are prompted to sign in", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/settings/privacy")
    assert has_element?(view, "[data-role='privacy-auth-required']")
  end
end
