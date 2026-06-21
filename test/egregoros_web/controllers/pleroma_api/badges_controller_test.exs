defmodule EgregorosWeb.PleromaAPI.BadgesControllerTest do
  use EgregorosWeb.ConnCase, async: true

  alias Egregoros.BadgeDefinition
  alias Egregoros.Repo
  alias Egregoros.Users

  test "POST /api/v1/pleroma/badges/issue issues a badge for admins", %{conn: conn} do
    {:ok, admin} = Users.create_local_user("badge_api_admin")
    {:ok, admin} = Users.set_admin(admin, true)
    {:ok, recipient} = Users.create_local_user("badge_api_recipient")

    badge_type =
      case Repo.get_by(BadgeDefinition, badge_type: "Founder") do
        %BadgeDefinition{} -> "Founder"
        _ -> "ApiFounder"
      end

    if badge_type != "Founder" do
      {:ok, _badge} =
        %BadgeDefinition{}
        |> BadgeDefinition.changeset(%{
          badge_type: badge_type,
          name: "Founder",
          description: "Founder badge.",
          narrative: "Granted for founding support.",
          disabled: false
        })
        |> Repo.insert()
    end

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, admin} end)

    conn =
      post(conn, "/api/v1/pleroma/badges/issue", %{
        "badge_type" => badge_type,
        "recipient_ap_id" => recipient.ap_id
      })

    assert %{"offer_id" => offer_id, "credential_id" => credential_id} = json_response(conn, 201)
    assert is_binary(offer_id)
    assert is_binary(credential_id)
  end

  test "POST /api/v1/pleroma/badges/issue rejects non-admins", %{conn: conn} do
    {:ok, user} = Users.create_local_user("badge_api_user")

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    conn =
      post(conn, "/api/v1/pleroma/badges/issue", %{
        "badge_type" => "Donator",
        "recipient_ap_id" => user.ap_id
      })

    assert json_response(conn, 403) == %{"error" => "forbidden"}
  end
end
