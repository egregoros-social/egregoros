defmodule EgregorosWeb.Components.NotificationItems.NotificationItemTest do
  use EgregorosWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias EgregorosWeb.Components.NotificationItems.NotificationItem

  test "dispatches Like entries to the LikeNotification component" do
    entry = %{
      type: "Like",
      actor: %{display_name: "Bob", handle: "@bob", avatar_url: nil},
      message: "Bob liked your post",
      message_emojis: [],
      target_path: "/@alice/1",
      notification: %{inserted_at: ~U[2025-01-01 00:00:00Z]}
    }

    html = render_component(&NotificationItem.notification_item/1, %{id: "n-1", entry: entry})

    assert html =~ ~s(data-role="notification")
    assert html =~ ~s(data-type="Like")
    assert html =~ ~s(data-role="notification-target")
    assert html =~ ~s(href="/@alice/1")
  end

  test "renders Like entries without a link when target_path is missing" do
    entry = %{
      type: "Like",
      actor: %{display_name: "Bob", handle: "@bob", avatar_url: nil},
      message: "Bob liked your post",
      message_emojis: [],
      target_path: nil,
      notification: %{inserted_at: ~U[2025-01-01 00:00:00Z]}
    }

    html = render_component(&NotificationItem.notification_item/1, %{id: "n-2", entry: entry})

    assert html =~ ~s(data-type="Like")
    refute html =~ ~s(data-role="notification-target")
  end

  test "dispatches Announce entries to the RepostNotification component" do
    entry = %{
      type: "Announce",
      actor: %{display_name: "Bob", handle: "@bob", avatar_url: nil},
      message: "Bob reposted your post",
      message_emojis: [],
      preview_html: "Preview",
      target_path: "/@alice/1",
      notification: %{inserted_at: ~U[2025-01-01 00:00:00Z]}
    }

    html = render_component(&NotificationItem.notification_item/1, %{id: "n-3", entry: entry})

    assert html =~ ~s(data-type="Announce")
    assert html =~ ~s(data-role="notification-preview")
    assert html =~ ~s(data-role="notification-target")
  end

  test "renders unknown notification types with the fallback card" do
    entry = %{
      type: "Mystery",
      actor: %{display_name: "Bob", handle: "@bob", avatar_url: nil},
      message: "Something happened",
      message_emojis: [],
      target_path: nil,
      notification: %{inserted_at: ~U[2025-01-01 00:00:00Z]}
    }

    html = render_component(&NotificationItem.notification_item/1, %{id: "n-4", entry: entry})

    assert html =~ ~s(data-type="Mystery")
    assert html =~ ~s(data-role="notification-message")
  end

  test "dispatches Offer entries to the OfferNotification component" do
    entry = %{
      type: "Offer",
      actor: %{display_name: "Issuer", handle: "@issuer", avatar_url: nil},
      message: "Issuer offered you a credential",
      message_emojis: [],
      notification: %{
        ap_id: "https://example.com/activities/offer/1",
        inserted_at: ~U[2025-01-01 00:00:00Z]
      }
    }

    html = render_component(&NotificationItem.notification_item/1, %{id: "n-5", entry: entry})

    assert html =~ ~s(data-type="Offer")
    assert html =~ ~s(data-role="offer-accept")
    assert html =~ ~s(data-role="offer-reject")
  end
end
