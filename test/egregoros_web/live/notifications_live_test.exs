defmodule EgregorosWeb.NotificationsLiveTest do
  use EgregorosWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Egregoros.Activities.Follow
  alias Egregoros.Activities.Accept
  alias Egregoros.Activities.EmojiReact
  alias Egregoros.Notifications
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Publish
  alias Egregoros.Relationships
  alias Egregoros.TestSupport.Fixtures
  alias Egregoros.Users
  alias EgregorosWeb.URL

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

  test "signed-out users see an auth required callout", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/notifications")
    assert has_element?(view, "[data-role='notifications-auth-required']", "Sign in")
  end

  test "signed-out views ignore streamed notifications", %{conn: conn, user: user, actor: actor} do
    {:ok, view, _html} = live(conn, "/notifications")

    assert {:ok, activity} = Pipeline.ingest(Follow.build(actor, user), local: true)

    send(view.pid, {:notification_created, activity})
    _ = :sys.get_state(view.pid)

    assert has_element?(view, "[data-role='notifications-auth-required']")
    refute has_element?(view, "#notification-#{activity.id}")
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

  test "notifications include loading skeleton placeholders when more pages exist", %{
    conn: conn,
    user: user,
    actor: actor
  } do
    for idx <- 1..21 do
      ap_id = "http://localhost:4000/activities/follow/skeleton-#{idx}"

      assert {:ok, _} =
               Pipeline.ingest(
                 %{
                   "id" => ap_id,
                   "type" => "Follow",
                   "actor" => actor.ap_id,
                   "object" => user.ap_id
                 },
                 local: true
               )
    end

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/notifications")

    assert has_element?(view, "[data-role='notifications-loading-more']")

    assert has_element?(
             view,
             "[data-role='notifications-loading-more'] [data-role='skeleton-status-card']"
           )
  end

  test "load more hides the button when there are no more notifications", %{
    conn: conn,
    user: user,
    actor: actor
  } do
    for idx <- 1..20 do
      ap_id = "http://localhost:4000/activities/follow/load-more-empty-#{idx}"

      assert {:ok, _} =
               Pipeline.ingest(
                 %{
                   "id" => ap_id,
                   "type" => "Follow",
                   "actor" => actor.ap_id,
                   "object" => user.ap_id
                 },
                 local: true
               )
    end

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/notifications")

    assert has_element?(view, "button[data-role='notifications-load-more']")

    view
    |> element("button[data-role='notifications-load-more']")
    |> render_click()

    refute has_element?(view, "button[data-role='notifications-load-more']")
  end

  test "streams new notifications into the list", %{conn: conn, user: user, actor: actor} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/notifications")

    assert {:ok, activity} = Pipeline.ingest(Follow.build(actor, user), local: true)

    send(view.pid, {:notification_created, activity})
    _ = :sys.get_state(view.pid)

    assert has_element?(view, "#notification-#{activity.id}")
  end

  test "notifications can be filtered without losing the list", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/notifications")

    assert has_element?(view, "#notifications-list[data-filter='all']")

    view
    |> element("button[data-role='notifications-filter'][data-filter='follows']")
    |> render_click()

    assert has_element?(view, "#notifications-list[data-filter='follows']")
  end

  test "notifications filter buttons expose active state for client-side UI", %{
    conn: conn,
    user: user
  } do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/notifications")

    assert has_element?(
             view,
             "button[data-role='notifications-filter'][data-filter='all'][data-active='true']"
           )

    assert has_element?(
             view,
             "button[data-role='notifications-filter'][data-filter='likes'][data-active='false']"
           )

    view
    |> element("button[data-role='notifications-filter'][data-filter='likes']")
    |> render_click()

    assert has_element?(view, "#notifications-list[data-filter='likes']")

    assert has_element?(
             view,
             "button[data-role='notifications-filter'][data-filter='likes'][data-active='true']"
           )

    assert has_element?(
             view,
             "button[data-role='notifications-filter'][data-filter='all'][data-active='false']"
           )
  end

  test "follow requests can be accepted from the notifications screen", %{
    conn: conn,
    user: user,
    actor: actor
  } do
    {:ok, user} = Users.update_profile(user, %{locked: true})

    assert {:ok, follow_object} = Pipeline.ingest(Follow.build(actor, user), local: true)

    assert %{id: relationship_id, activity_ap_id: activity_ap_id} =
             Relationships.get_by_type_actor_object("FollowRequest", actor.ap_id, user.ap_id)

    assert activity_ap_id == follow_object.ap_id

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/notifications")

    view
    |> element("button[data-role='notifications-filter'][data-filter='requests']")
    |> render_click()

    assert has_element?(view, "#follow-request-#{relationship_id}")

    view
    |> element("button[data-role='follow-request-accept'][phx-value-id='#{relationship_id}']")
    |> render_click()

    assert Relationships.get_by_type_actor_object("FollowRequest", actor.ap_id, user.ap_id) == nil
    assert Relationships.get_by_type_actor_object("Follow", actor.ap_id, user.ap_id)
  end

  test "follow requests can be rejected from the notifications screen", %{
    conn: conn,
    user: user,
    actor: actor
  } do
    {:ok, user} = Users.update_profile(user, %{locked: true})

    assert {:ok, follow_object} = Pipeline.ingest(Follow.build(actor, user), local: true)

    assert %{id: relationship_id, activity_ap_id: activity_ap_id} =
             Relationships.get_by_type_actor_object("FollowRequest", actor.ap_id, user.ap_id)

    assert activity_ap_id == follow_object.ap_id

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/notifications")

    view
    |> element("button[data-role='notifications-filter'][data-filter='requests']")
    |> render_click()

    assert has_element?(view, "#follow-request-#{relationship_id}")

    view
    |> element("button[data-role='follow-request-reject'][phx-value-id='#{relationship_id}']")
    |> render_click()

    assert Relationships.get_by_type_actor_object("FollowRequest", actor.ap_id, user.ap_id) == nil
    assert Relationships.get_by_type_actor_object("Follow", actor.ap_id, user.ap_id) == nil
  end

  test "offer notifications can be accepted from the notifications screen", %{
    conn: conn,
    user: user
  } do
    credential =
      Fixtures.json!("openbadge_vc.json")
      |> Map.put("issuer", "https://example.com/users/issuer")
      |> Map.put("to", [user.ap_id])
      |> put_in(["credentialSubject", "id"], user.ap_id)

    offer = %{
      "id" => "https://example.com/activities/offer/live-accept",
      "type" => "Offer",
      "actor" => "https://example.com/users/issuer",
      "to" => [user.ap_id],
      "object" => credential,
      "published" => "2026-01-29T00:00:00Z"
    }

    assert {:ok, offer_object} =
             Pipeline.ingest(offer, local: false, inbox_user_ap_id: user.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/notifications")

    assert has_element?(view, "#notification-#{offer_object.id}")

    view
    |> element("button[data-role='offer-accept'][phx-value-id='#{offer_object.ap_id}']")
    |> render_click()

    assert Objects.get_by_type_actor_object("Accept", user.ap_id, offer_object.ap_id)

    assert has_element?(
             view,
             "#notification-#{offer_object.id} [data-role='offer-response-status']",
             "You accepted this badge."
           )

    refute has_element?(
             view,
             "#notification-#{offer_object.id} button[data-role='offer-accept']"
           )

    refute has_element?(
             view,
             "#notification-#{offer_object.id} button[data-role='offer-reject']"
           )
  end

  test "offer notifications can be rejected from the notifications screen", %{
    conn: conn,
    user: user
  } do
    credential =
      Fixtures.json!("openbadge_vc.json")
      |> Map.put("issuer", "https://example.com/users/issuer")
      |> Map.put("to", [user.ap_id])
      |> put_in(["credentialSubject", "id"], user.ap_id)

    offer = %{
      "id" => "https://example.com/activities/offer/live-reject",
      "type" => "Offer",
      "actor" => "https://example.com/users/issuer",
      "to" => [user.ap_id],
      "object" => credential,
      "published" => "2026-01-29T00:00:00Z"
    }

    assert {:ok, offer_object} =
             Pipeline.ingest(offer, local: false, inbox_user_ap_id: user.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/notifications")

    assert has_element?(view, "#notification-#{offer_object.id}")

    view
    |> element("button[data-role='offer-reject'][phx-value-id='#{offer_object.ap_id}']")
    |> render_click()

    assert Objects.get_by_type_actor_object("Reject", user.ap_id, offer_object.ap_id)

    assert has_element?(
             view,
             "#notification-#{offer_object.id} [data-role='offer-response-status']",
             "You rejected this badge."
           )

    refute has_element?(
             view,
             "#notification-#{offer_object.id} button[data-role='offer-accept']"
           )

    refute has_element?(
             view,
             "#notification-#{offer_object.id} button[data-role='offer-reject']"
           )
  end

  test "offer notifications include credential details", %{conn: conn, user: user} do
    credential =
      Fixtures.json!("openbadge_vc.json")
      |> Map.put("issuer", "https://example.com/users/issuer")
      |> Map.put("to", [user.ap_id])
      |> put_in(["credentialSubject", "id"], user.ap_id)
      |> put_in(["credentialSubject", "achievement", "name"], "Contributor")
      |> put_in(
        ["credentialSubject", "achievement", "description"],
        "Awarded for supporting the community."
      )

    offer = %{
      "id" => "https://example.com/activities/offer/live-details",
      "type" => "Offer",
      "actor" => "https://example.com/users/issuer",
      "to" => [user.ap_id],
      "object" => credential,
      "published" => "2026-01-29T00:00:00Z"
    }

    assert {:ok, offer_object} =
             Pipeline.ingest(offer, local: false, inbox_user_ap_id: user.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/notifications")

    assert has_element?(
             view,
             "#notification-#{offer_object.id} [data-role='offer-title']",
             "Contributor"
           )

    assert has_element?(
             view,
             "#notification-#{offer_object.id} [data-role='offer-description']",
             "Awarded for supporting the community."
           )

    assert has_element?(
             view,
             "#notification-#{offer_object.id} [data-role='offer-issuer-ap-id']",
             "https://example.com/users/issuer"
           )
  end

  test "offer notifications use the actor ap id in the message", %{conn: conn, user: user} do
    credential =
      Fixtures.json!("openbadge_vc.json")
      |> Map.put("issuer", "https://example.com/users/issuer")
      |> Map.put("to", [user.ap_id])
      |> put_in(["credentialSubject", "id"], user.ap_id)

    offer = %{
      "id" => "https://example.com/activities/offer/live-message",
      "type" => "Offer",
      "actor" => "https://example.com/users/issuer",
      "to" => [user.ap_id],
      "object" => credential,
      "published" => "2026-01-29T00:00:00Z"
    }

    assert {:ok, offer_object} =
             Pipeline.ingest(offer, local: false, inbox_user_ap_id: user.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/notifications")

    assert has_element?(
             view,
             "#notification-#{offer_object.id} [data-role='notification-message']",
             "https://example.com/users/issuer offered you a badge"
           )
  end

  test "offer notifications include badge images when available", %{conn: conn, user: user} do
    credential =
      Fixtures.json!("openbadge_vc.json")
      |> Map.put("issuer", "https://example.com/users/issuer")
      |> Map.put("to", [user.ap_id])
      |> put_in(["credentialSubject", "id"], user.ap_id)

    offer = %{
      "id" => "https://example.com/activities/offer/live-image",
      "type" => "Offer",
      "actor" => "https://example.com/users/issuer",
      "to" => [user.ap_id],
      "object" => credential,
      "published" => "2026-01-29T00:00:00Z"
    }

    assert {:ok, offer_object} =
             Pipeline.ingest(offer, local: false, inbox_user_ap_id: user.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/notifications")

    assert has_element?(
             view,
             "#notification-#{offer_object.id} img[data-role='offer-badge-image'][src='https://example.com/badges/donator.png']"
           )
  end

  test "offer notifications link to the accepted badge", %{conn: conn, user: user} do
    credential =
      Fixtures.json!("openbadge_vc.json")
      |> Map.put("issuer", "https://example.com/users/issuer")
      |> Map.put("to", [user.ap_id])
      |> put_in(["credentialSubject", "id"], user.ap_id)

    offer = %{
      "id" => "https://example.com/activities/offer/live-link",
      "type" => "Offer",
      "actor" => "https://example.com/users/issuer",
      "to" => [user.ap_id],
      "object" => credential,
      "published" => "2026-01-29T00:00:00Z"
    }

    assert {:ok, offer_object} =
             Pipeline.ingest(offer, local: false, inbox_user_ap_id: user.ap_id)

    assert {:ok, accept_object} =
             Pipeline.ingest(Accept.build(user, offer_object), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/notifications")

    assert has_element?(
             view,
             "#notification-#{offer_object.id} [data-role='offer-response-status'] + [data-role='offer-badge-link']"
           )

    assert has_element?(
             view,
             "#notification-#{offer_object.id} [data-role='offer-badge-link'][href='/@#{user.nickname}/badges/#{accept_object.id}']"
           )
  end

  test "notifications filters ignore invalid values", %{conn: conn, user: user} do
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/notifications")

    assert has_element?(view, "#notifications-list[data-filter='all']")

    _html = render_click(view, "set_notifications_filter", %{"filter" => "nope"})

    assert has_element?(view, "#notifications-list[data-filter='all']")
  end

  test "emoji reaction notifications render custom emoji and link to the target post", %{
    conn: conn,
    user: user,
    actor: actor
  } do
    assert {:ok, create} = Publish.post_note(user, "Hello")
    note = Objects.get_by_ap_id(create.object)

    assert {:ok, _} =
             Pipeline.ingest(
               EmojiReact.build(actor, note, ":flow_think:")
               |> Map.put("tag", [
                 %{
                   "type" => "Emoji",
                   "name" => ":flow_think:",
                   "icon" => %{"url" => "https://cdn.example/emoji.png"}
                 }
               ]),
               local: true
             )

    [notification] = Notifications.list_for_user(user, limit: 1)
    note_uuid = URL.local_object_uuid(note.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/notifications")

    assert has_element?(view, "#notification-#{notification.id} img.emoji[alt=':flow_think:']")

    assert has_element?(
             view,
             "#notification-#{notification.id} [data-role='notification-target'][href='/@alice/#{note_uuid}']"
           )
  end

  test "mention notifications include a link to the mentioned status", %{
    conn: conn,
    user: user,
    actor: actor
  } do
    assert {:ok, mention_create} = Publish.post_note(actor, "@alice Hello there")
    mention_note = Objects.get_by_ap_id(mention_create.object)
    mention_uuid = URL.local_object_uuid(mention_note.ap_id)

    [notification] = Notifications.list_for_user(user, limit: 1)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/notifications")

    assert has_element?(
             view,
             "#notification-#{notification.id} [data-role='notification-target'][href='/@bob/#{mention_uuid}']"
           )
  end
end
