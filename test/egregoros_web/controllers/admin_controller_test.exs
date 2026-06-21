defmodule EgregorosWeb.AdminControllerTest do
  use EgregorosWeb.ConnCase, async: true

  import Mox

  alias LazyHTML
  alias Egregoros.BadgeDefinition
  alias Egregoros.Federation.InstanceActor
  alias Egregoros.InstanceSettings
  alias Egregoros.Relationships
  alias Egregoros.Relays
  alias Egregoros.Repo
  alias Egregoros.Users
  alias Egregoros.Workers.DeliverActivity

  test "GET /admin redirects guests to login", %{conn: conn} do
    conn = get(conn, "/admin")
    assert redirected_to(conn) == "/login"
  end

  test "GET /admin rejects non-admins", %{conn: conn} do
    {:ok, user} = Users.create_local_user("bob")
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})

    conn = get(conn, "/admin")
    assert response(conn, 403) =~ "Forbidden"
  end

  test "GET /admin renders for admins", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")
    {:ok, user} = Users.set_admin(user, true)
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})

    conn = get(conn, "/admin")
    html = html_response(conn, 200)
    assert html =~ "Admin settings"
    assert html =~ "Relays"
    assert html =~ "Oban dashboard"
    assert html =~ "Live dashboard"
    assert html =~ "/admin/dashboard"
  end

  test "GET /admin disables badge issue button by default", %{conn: conn} do
    {:ok, user} = Users.create_local_user("badge_admin_ui")
    {:ok, user} = Users.set_admin(user, true)
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})

    conn = get(conn, "/admin")
    html = html_response(conn, 200)

    document = LazyHTML.from_fragment(html)
    assert LazyHTML.filter(document, "#badge-issue-submit[disabled]") != []
  end

  test "POST /admin/registrations updates registration settings", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")
    {:ok, user} = Users.set_admin(user, true)
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})

    csrf_token = Phoenix.Controller.get_csrf_token()

    conn =
      post(conn, "/admin/registrations", %{
        "_csrf_token" => csrf_token,
        "registrations" => %{"open" => "false"}
      })

    assert redirected_to(conn) == "/admin"
    refute InstanceSettings.registrations_open?()
  end

  test "POST /admin/relays subscribes the internal actor to the relay", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")
    {:ok, user} = Users.set_admin(user, true)
    {:ok, internal} = InstanceActor.get_actor()

    relay_ap_id = "https://relay.example/actor"
    relay_inbox = "https://relay.example/inbox"
    relay_outbox = "https://relay.example/outbox"

    expect(Egregoros.HTTP.Mock, :get, fn url, headers ->
      assert url == relay_ap_id
      assert List.keyfind(headers, "accept", 0)
      assert List.keyfind(headers, "user-agent", 0)

      {:ok,
       %{
         status: 200,
         body: %{
           "id" => relay_ap_id,
           "type" => "Service",
           "preferredUsername" => "relay",
           "inbox" => relay_inbox,
           "outbox" => relay_outbox,
           "publicKey" => %{
             "id" => relay_ap_id <> "#main-key",
             "owner" => relay_ap_id,
             "publicKeyPem" => "-----BEGIN PUBLIC KEY-----\nMIIB\n-----END PUBLIC KEY-----"
           }
         },
         headers: []
       }}
    end)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})

    csrf_token = Phoenix.Controller.get_csrf_token()

    conn =
      post(conn, "/admin/relays", %{
        "_csrf_token" => csrf_token,
        "relay" => %{"ap_id" => relay_ap_id}
      })

    assert redirected_to(conn) == "/admin"
    assert Enum.any?(Relays.list_relays(), &(&1.ap_id == relay_ap_id))

    assert_enqueued(
      worker: DeliverActivity,
      args: %{
        "user_id" => internal.id,
        "inbox_url" => relay_inbox,
        "activity" => %{"type" => "Follow", "object" => relay_ap_id}
      }
    )
  end

  test "POST /admin/badges/issue issues a badge offer", %{conn: conn} do
    {:ok, admin} = Users.create_local_user("admin")
    {:ok, admin} = Users.set_admin(admin, true)
    {:ok, recipient} = Users.create_local_user("badge_admin_recipient")

    badge_type =
      case Egregoros.Repo.get_by(Egregoros.BadgeDefinition, badge_type: "Donator") do
        %Egregoros.BadgeDefinition{} -> "Donator"
        _ -> "AdminDonator"
      end

    if badge_type != "Donator" do
      {:ok, _badge} =
        %Egregoros.BadgeDefinition{}
        |> Egregoros.BadgeDefinition.changeset(%{
          badge_type: badge_type,
          name: "Donator",
          description: "Supporter badge.",
          narrative: "Granted for support.",
          disabled: false
        })
        |> Egregoros.Repo.insert()
    end

    conn = Plug.Test.init_test_session(conn, %{user_id: admin.id})
    csrf_token = Phoenix.Controller.get_csrf_token()

    conn =
      post(conn, "/admin/badges/issue", %{
        "_csrf_token" => csrf_token,
        "badge_issue" => %{
          "badge_type" => badge_type,
          "recipient_ap_id" => recipient.ap_id,
          "expires_on" => "2026-02-01"
        }
      })

    assert redirected_to(conn) == "/admin"

    [offer_object | _] =
      Egregoros.Objects.list_by_type_actor("Offer", InstanceActor.ap_id(), limit: 1)

    assert %Egregoros.Object{} = offer_object

    credential_object = Egregoros.Objects.get_by_ap_id(offer_object.object)
    assert %Egregoros.Object{} = credential_object

    assert %{"validFrom" => valid_from, "validUntil" => valid_until} = credential_object.data

    {:ok, valid_from_dt, _} = DateTime.from_iso8601(valid_from)
    {:ok, valid_until_dt, _} = DateTime.from_iso8601(valid_until)

    assert DateTime.to_date(valid_from_dt) == Date.utc_today()
    assert DateTime.to_date(valid_until_dt) == ~D[2026-02-01]
    assert DateTime.to_time(valid_until_dt) == ~T[23:59:59]
  end

  test "POST /admin/badges/offers/:id/rescind rescinds a badge offer", %{conn: conn} do
    {:ok, admin} = Users.create_local_user("badge_offer_admin")
    {:ok, admin} = Users.set_admin(admin, true)
    {:ok, recipient} = Users.create_local_user("badge_offer_recipient")

    badge_type =
      case Egregoros.Repo.get_by(Egregoros.BadgeDefinition, badge_type: "Donator") do
        %Egregoros.BadgeDefinition{} -> "Donator"
        _ -> "AdminOfferDonator"
      end

    if badge_type != "Donator" do
      {:ok, _badge} =
        %Egregoros.BadgeDefinition{}
        |> Egregoros.BadgeDefinition.changeset(%{
          badge_type: badge_type,
          name: "Donator",
          description: "Supporter badge.",
          narrative: "Granted for support.",
          disabled: false
        })
        |> Egregoros.Repo.insert()
    end

    {:ok, %{offer: offer}} = Egregoros.Badges.issue_badge(badge_type, recipient.ap_id)

    assert Egregoros.Relationships.get_by_type_actor_object(
             "OfferPending",
             recipient.ap_id,
             offer.ap_id
           )

    conn = Plug.Test.init_test_session(conn, %{user_id: admin.id})
    csrf_token = Phoenix.Controller.get_csrf_token()

    conn =
      post(conn, "/admin/badges/offers/#{offer.id}/rescind", %{
        "_csrf_token" => csrf_token
      })

    assert redirected_to(conn) == "/admin"
    assert is_nil(Egregoros.Objects.get(offer.id))
    assert is_nil(Egregoros.Objects.get_by_ap_id(offer.ap_id))

    refute Egregoros.Relationships.get_by_type_actor_object(
             "OfferPending",
             recipient.ap_id,
             offer.ap_id
           )

    assert %Egregoros.Object{} =
             Egregoros.Objects.get_by_type_actor_object(
               "Undo",
               InstanceActor.ap_id(),
               offer.ap_id
             )
  end

  test "DELETE /admin/relays/:id unsubscribes the internal actor from the relay", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")
    {:ok, user} = Users.set_admin(user, true)
    {:ok, internal} = InstanceActor.get_actor()

    relay_ap_id = "https://relay.example/actor"
    relay_inbox = "https://relay.example/inbox"
    relay_outbox = "https://relay.example/outbox"

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == relay_ap_id

      {:ok,
       %{
         status: 200,
         body: %{
           "id" => relay_ap_id,
           "type" => "Service",
           "preferredUsername" => "relay",
           "inbox" => relay_inbox,
           "outbox" => relay_outbox,
           "publicKey" => %{
             "id" => relay_ap_id <> "#main-key",
             "owner" => relay_ap_id,
             "publicKeyPem" => "-----BEGIN PUBLIC KEY-----\nMIIB\n-----END PUBLIC KEY-----"
           }
         },
         headers: []
       }}
    end)

    csrf_token = Phoenix.Controller.get_csrf_token()

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})

    _ =
      post(conn, "/admin/relays", %{
        "_csrf_token" => csrf_token,
        "relay" => %{"ap_id" => relay_ap_id}
      })

    [%{id: relay_id, ap_id: ^relay_ap_id}] = Relays.list_relays()

    relationship =
      Relationships.get_by_type_actor_object("Follow", internal.ap_id, relay_ap_id) ||
        Relationships.get_by_type_actor_object("FollowRequest", internal.ap_id, relay_ap_id)

    assert %{activity_ap_id: follow_ap_id} = relationship

    conn = Plug.Test.init_test_session(build_conn(), %{user_id: user.id})

    conn =
      delete(conn, "/admin/relays/#{relay_id}", %{
        "_csrf_token" => csrf_token
      })

    assert redirected_to(conn) == "/admin"
    assert Relays.list_relays() == []

    assert Relationships.get_by_type_actor_object("Follow", internal.ap_id, relay_ap_id) == nil

    assert Relationships.get_by_type_actor_object("FollowRequest", internal.ap_id, relay_ap_id) ==
             nil

    assert_enqueued(
      worker: DeliverActivity,
      args: %{
        "user_id" => internal.id,
        "inbox_url" => relay_inbox,
        "activity" => %{"type" => "Undo", "object" => follow_ap_id}
      }
    )
  end

  test "POST /admin/badges/:id updates badge definition images via instance actor storage", %{
    conn: conn
  } do
    {:ok, admin} = Users.create_local_user("badge_admin")
    {:ok, admin} = Users.set_admin(admin, true)
    {:ok, instance_actor} = InstanceActor.get_actor()

    badge =
      case Repo.get_by(BadgeDefinition, badge_type: "Donator") do
        %BadgeDefinition{} = badge ->
          badge

        _ ->
          {:ok, badge} =
            %BadgeDefinition{}
            |> BadgeDefinition.changeset(%{
              badge_type: "AdminDonatorImage",
              name: "Donator",
              description: "Supporter badge.",
              narrative: "Granted for support.",
              disabled: false
            })
            |> Repo.insert()

          badge
      end

    upload = %Plug.Upload{
      path: fixture_path("DSCN0010.png"),
      filename: "badge.png",
      content_type: "image/png"
    }

    expect(Egregoros.MediaStorage.Mock, :store_media, fn ^instance_actor,
                                                         %Plug.Upload{filename: "badge.png"} ->
      {:ok, "/uploads/media/#{instance_actor.id}/badge.png"}
    end)

    conn = Plug.Test.init_test_session(conn, %{user_id: admin.id})
    csrf_token = Phoenix.Controller.get_csrf_token()

    conn =
      post(conn, "/admin/badges/#{badge.id}", %{
        "_csrf_token" => csrf_token,
        "badge_definition" => %{"image" => upload}
      })

    assert redirected_to(conn) == "/admin"

    assert %BadgeDefinition{image_url: image_url} = Repo.get(BadgeDefinition, badge.id)

    assert image_url ==
             EgregorosWeb.Endpoint.url() <> "/uploads/media/#{instance_actor.id}/badge.png"
  end

  test "POST /admin/badges/:id handles malformed badge ids without crashing", %{conn: conn} do
    {:ok, admin} = Users.create_local_user("badge_admin_invalid_id")
    {:ok, admin} = Users.set_admin(admin, true)

    conn = Plug.Test.init_test_session(conn, %{user_id: admin.id})
    csrf_token = Phoenix.Controller.get_csrf_token()

    conn =
      post(conn, "/admin/badges/not_a_flake_id__xx", %{
        "_csrf_token" => csrf_token,
        "badge_definition" => %{}
      })

    assert redirected_to(conn) == "/admin"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Could not update badge."
  end

  test "admin endpoints return 422 for malformed params", %{conn: conn} do
    {:ok, admin} = Users.create_local_user("admin_unprocessable")
    {:ok, admin} = Users.set_admin(admin, true)

    conn = Plug.Test.init_test_session(conn, %{user_id: admin.id})
    csrf_token = Phoenix.Controller.get_csrf_token()

    conn =
      post(conn, "/admin/registrations", %{
        "_csrf_token" => csrf_token
      })

    assert response(conn, 422) =~ "Unprocessable Entity"

    conn =
      post(conn, "/admin/relays", %{
        "_csrf_token" => csrf_token
      })

    assert response(conn, 422) =~ "Unprocessable Entity"

    conn =
      post(conn, "/admin/badges/invalid", %{
        "_csrf_token" => csrf_token
      })

    assert response(conn, 422) =~ "Unprocessable Entity"
  end

  defp fixture_path(filename) do
    Path.expand(Path.join(["test", "fixtures", filename]), File.cwd!())
  end
end
