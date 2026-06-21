defmodule EgregorosWeb.BadgesLiveTest do
  use EgregorosWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Egregoros.Activities.Accept
  alias Egregoros.Activities.Note
  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Repo
  alias Egregoros.TestSupport.Fixtures
  alias Egregoros.Users

  setup do
    {:ok, recipient} = Users.create_local_user("badge_recipient")

    %{recipient: recipient}
  end

  test "badges list renders accepted badges with validity", %{conn: conn, recipient: recipient} do
    {_offer, accept} = accept_badge_offer(recipient)

    {:ok, view, _html} = live(conn, "/@#{recipient.nickname}/badges")

    assert has_element?(view, "#badge-#{accept.id}")

    assert has_element?(
             view,
             "#badge-#{accept.id} [data-role='badge-title']",
             "Donator"
           )

    assert has_element?(
             view,
             "#badge-#{accept.id} [data-role='badge-validity']",
             "Valid"
           )
  end

  test "badge detail renders the badge card and image", %{conn: conn, recipient: recipient} do
    {_offer, accept} = accept_badge_offer(recipient)

    {:ok, view, _html} = live(conn, "/@#{recipient.nickname}/badges/#{accept.id}")

    assert has_element?(view, "[data-role='badge-detail']")
    assert has_element?(view, "[data-role='badge-detail'] [data-role='badge-title']", "Donator")
    assert has_element?(view, "[data-role='badge-detail'] img[data-role='badge-image']")
  end

  test "badges list shows a share button for signed-in users", %{
    conn: conn,
    recipient: recipient
  } do
    {_offer, accept} = accept_badge_offer(recipient)

    conn = Plug.Test.init_test_session(conn, %{user_id: recipient.id})

    {:ok, view, _html} = live(conn, "/@#{recipient.nickname}/badges")

    assert has_element?(view, "#badge-#{accept.id} [data-role='badge-share']")
  end

  test "badges list shows a copy url button", %{conn: conn, recipient: recipient} do
    {_offer, accept} = accept_badge_offer(recipient)

    {:ok, view, _html} = live(conn, "/@#{recipient.nickname}/badges")

    assert has_element?(view, "#badge-#{accept.id} [data-role='badge-copy-url']")
  end

  test "sharing a badge shows a toast message", %{conn: conn, recipient: recipient} do
    {_offer, accept} = accept_badge_offer(recipient)

    conn = Plug.Test.init_test_session(conn, %{user_id: recipient.id})

    {:ok, view, _html} = live(conn, "/@#{recipient.nickname}/badges")

    view
    |> element("#badge-#{accept.id} [data-role='badge-share']")
    |> render_click()

    assert has_element?(view, "[data-role='toast']", "Badge shared.")
  end

  test "badge detail shows a copy url button", %{conn: conn, recipient: recipient} do
    {_offer, accept} = accept_badge_offer(recipient)

    {:ok, view, _html} = live(conn, "/@#{recipient.nickname}/badges/#{accept.id}")

    assert has_element?(view, "[data-role='badge-detail'] [data-role='badge-copy-url']")
  end

  test "sharing a badge twice toggles it back off", %{conn: conn, recipient: recipient} do
    {_offer, accept} = accept_badge_offer(recipient)

    conn = Plug.Test.init_test_session(conn, %{user_id: recipient.id})

    {:ok, view, _html} = live(conn, "/@#{recipient.nickname}/badges")

    view
    |> element("#badge-#{accept.id} [data-role='badge-share']")
    |> render_click()

    assert has_element?(view, "[data-role='toast']", "Badge shared.")

    view
    |> element("#badge-#{accept.id} [data-role='badge-share']")
    |> render_click()

    assert has_element?(view, "[data-role='toast']", "Badge unshared.")
  end

  test "badge sharing requires a signed-in user", %{conn: conn, recipient: recipient} do
    {_offer, _accept} = accept_badge_offer(recipient)

    {:ok, view, _html} = live(conn, "/@#{recipient.nickname}/badges")

    _ = render_click(view, "toggle_repost", %{"id" => "invalid"})

    assert has_element?(view, "[data-role='toast']", "Register to share badges.")
  end

  test "badge sharing ignores invalid post ids", %{conn: conn, recipient: recipient} do
    {_offer, _accept} = accept_badge_offer(recipient)

    conn = Plug.Test.init_test_session(conn, %{user_id: recipient.id})

    {:ok, view, _html} = live(conn, "/@#{recipient.nickname}/badges")

    _ = render_click(view, "toggle_repost", %{"id" => "not_a_flake_id__xx"})

    refute has_element?(view, "[data-role='toast']", "Badge shared.")
    refute has_element?(view, "[data-role='toast']", "Badge unshared.")
  end

  test "reposting non-badge objects does not show badge share toasts", %{
    conn: conn,
    recipient: recipient
  } do
    {:ok, note} = Pipeline.ingest(Note.build(recipient, "Non-badge post"), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: recipient.id})

    {:ok, view, _html} = live(conn, "/@#{recipient.nickname}/badges")

    _ = render_click(view, "toggle_repost", %{"id" => note.id})

    refute has_element?(view, "[data-role='toast']", "Badge shared.")
    refute has_element?(view, "[data-role='toast']", "Badge unshared.")
  end

  test "badge detail shows a fallback when the badge is missing", %{
    conn: conn,
    recipient: recipient
  } do
    {:ok, view, _html} = live(conn, "/@#{recipient.nickname}/badges/invalid")

    assert has_element?(view, "#badges-shell")
    assert render(view) =~ "Badge not found"
  end

  test "badges view shows profile not found for unknown handles", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/@does-not-exist/badges")

    assert has_element?(view, "#badges-shell")
    assert render(view) =~ "Profile not found"
  end

  test "badges list supports embedded offers and credentials", %{conn: conn, recipient: recipient} do
    accept = insert_embedded_accept(recipient, valid_from_offset: -3600, valid_until_offset: 3600)

    {:ok, view, _html} = live(conn, "/@#{recipient.nickname}/badges")

    assert has_element?(view, "#badge-#{accept.id}")
    assert has_element?(view, "#badge-#{accept.id} img[data-role='badge-image']")
  end

  test "badges list shows expired and not-yet-valid badges", %{conn: conn, recipient: recipient} do
    expired =
      insert_embedded_accept(recipient, valid_from_offset: -86_400, valid_until_offset: -3600)

    future =
      insert_embedded_accept(recipient, valid_from_offset: 3600, valid_until_offset: 86_400)

    {:ok, view, _html} = live(conn, "/@#{recipient.nickname}/badges")

    assert has_element?(view, "#badge-#{expired.id} [data-role='badge-validity']", "Expired")
    assert has_element?(view, "#badge-#{future.id} [data-role='badge-validity']", "Not yet valid")
  end

  test "badge images support multiple shapes and missing values", %{
    conn: conn,
    recipient: recipient
  } do
    string_image =
      insert_embedded_accept(recipient,
        image: "/uploads/media/badges/donator-string.png",
        valid_from_offset: -3600,
        valid_until_offset: 3600
      )

    id_image =
      insert_embedded_accept(recipient,
        image: %{"id" => "/uploads/media/badges/donator-id.png"},
        valid_from_offset: -3600,
        valid_until_offset: 3600
      )

    no_image =
      insert_embedded_accept(recipient,
        image: nil,
        valid_from_offset: -3600,
        valid_until_offset: 3600
      )

    {:ok, view, _html} = live(conn, "/@#{recipient.nickname}/badges")

    assert has_element?(view, "#badge-#{string_image.id} img[data-role='badge-image']")
    assert has_element?(view, "#badge-#{id_image.id} img[data-role='badge-image']")
    refute has_element?(view, "#badge-#{no_image.id} img[data-role='badge-image']")
  end

  test "badge detail can be loaded directly from the credential ap id", %{
    conn: conn,
    recipient: recipient
  } do
    {offer, _accept} = accept_badge_offer(recipient)
    credential_ap_id = offer.data["object"]["id"]
    encoded_id = URI.encode_www_form(credential_ap_id)

    assert %Object{type: "VerifiableCredential"} = Objects.get_by_ap_id(credential_ap_id)

    {:ok, view, _html} = live(conn, "/@#{recipient.nickname}/badges/#{encoded_id}")

    assert has_element?(view, "[data-role='badge-detail']")
  end

  defp accept_badge_offer(recipient) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    credential =
      Fixtures.json!("openbadge_vc.json")
      |> Map.put("issuer", "https://example.com/users/issuer")
      |> Map.put("to", [recipient.ap_id])
      |> put_in(["credentialSubject", "id"], recipient.ap_id)
      |> Map.put("validFrom", DateTime.add(now, -3600, :second) |> DateTime.to_iso8601())
      |> Map.put("validUntil", DateTime.add(now, 86_400, :second) |> DateTime.to_iso8601())

    offer = %{
      "id" => "https://example.com/activities/offer/#{Ecto.UUID.generate()}",
      "type" => "Offer",
      "actor" => "https://example.com/users/issuer",
      "to" => [recipient.ap_id],
      "object" => credential,
      "published" => DateTime.to_iso8601(now)
    }

    {:ok, offer_object} =
      Pipeline.ingest(offer, local: false, inbox_user_ap_id: recipient.ap_id)

    {:ok, accept_object} = Pipeline.ingest(Accept.build(recipient, offer_object), local: true)

    {offer_object, accept_object}
  end

  defp insert_embedded_accept(%Egregoros.User{} = recipient, opts) when is_list(opts) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    valid_from_offset = Keyword.get(opts, :valid_from_offset, -3600)
    valid_until_offset = Keyword.get(opts, :valid_until_offset, 3600)

    valid_from =
      if is_integer(valid_from_offset),
        do: DateTime.add(now, valid_from_offset, :second),
        else: nil

    valid_until =
      if is_integer(valid_until_offset),
        do: DateTime.add(now, valid_until_offset, :second),
        else: nil

    issuer_ap_id = "https://example.com/users/issuer"
    credential_ap_id = "https://example.com/credentials/" <> Ecto.UUID.generate()

    image = Keyword.get(opts, :image, %{"url" => "/uploads/media/badges/donator.png"})

    achievement =
      %{
        "id" => "https://example.com/badges/" <> Ecto.UUID.generate(),
        "type" => "Achievement",
        "name" => "Donator",
        "description" => "Supporter badge."
      }
      |> maybe_put("image", image)

    credential_data =
      %{
        "id" => credential_ap_id,
        "type" => "VerifiableCredential",
        "issuer" => issuer_ap_id,
        "credentialSubject" => %{
          "id" => recipient.ap_id,
          "achievement" => achievement
        },
        "validFrom" => if(valid_from, do: DateTime.to_iso8601(valid_from), else: nil),
        "validUntil" => if(valid_until, do: DateTime.to_iso8601(valid_until), else: nil)
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    offer_data = %{
      "id" => "https://example.com/activities/offer/" <> Ecto.UUID.generate(),
      "type" => "Offer",
      "actor" => issuer_ap_id,
      "to" => [recipient.ap_id],
      "object" => credential_data,
      "published" => DateTime.to_iso8601(now)
    }

    accept_data = %{
      "id" => "https://example.com/activities/accept/" <> Ecto.UUID.generate(),
      "type" => "Accept",
      "actor" => recipient.ap_id,
      "to" => [recipient.ap_id],
      "object" => offer_data,
      "published" => DateTime.to_iso8601(now)
    }

    {:ok, accept} =
      %Object{}
      |> Object.changeset(%{
        ap_id: accept_data["id"],
        type: "Accept",
        actor: recipient.ap_id,
        local: true,
        published: now,
        data: accept_data
      })
      |> Repo.insert()

    accept
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
