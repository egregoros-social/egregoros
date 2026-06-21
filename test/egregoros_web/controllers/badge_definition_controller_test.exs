defmodule EgregorosWeb.BadgeDefinitionControllerTest do
  use EgregorosWeb.ConnCase, async: true

  alias Egregoros.BadgeDefinition
  alias Egregoros.Repo
  alias EgregorosWeb.Endpoint

  test "GET /badges/:id returns the badge definition json-ld", %{conn: conn} do
    {:ok, badge} =
      %BadgeDefinition{}
      |> BadgeDefinition.changeset(%{
        badge_type: "donator",
        name: "Donator",
        description: "Awarded to users who have made a financial contribution to the instance.",
        narrative: "Make any monetary donation to support the instance.",
        image_url: "https://example.com/badges/donator.png",
        disabled: false
      })
      |> Repo.insert()

    conn = get(conn, "/badges/#{badge.id}")
    assert conn.status == 200

    [content_type] = get_resp_header(conn, "content-type")
    assert String.contains?(content_type, "application/ld+json")

    decoded = Jason.decode!(conn.resp_body)

    assert decoded["@context"] == [
             "https://www.w3.org/ns/credentials/v2",
             "https://purl.imsglobal.org/spec/ob/v3p0/context-3.0.3.json"
           ]

    assert decoded["id"] == Endpoint.url() <> "/badges/" <> badge.id
    assert decoded["type"] == "Achievement"
    assert decoded["name"] == badge.name
    assert decoded["description"] == badge.description
    assert decoded["criteria"]["narrative"] == badge.narrative
    assert decoded["image"]["id"] == "https://example.com/badges/donator.png"
    assert decoded["image"]["type"] == "Image"
  end

  test "GET /badges/:id returns 404 for unknown badge", %{conn: conn} do
    conn = get(conn, "/badges/invalid")
    assert conn.status == 404
  end

  test "GET /badges/:id returns 404 for malformed badge ids", %{conn: conn} do
    conn = get(conn, "/badges/not_a_flake_id__xx")
    assert conn.status == 404
  end
end
