defmodule EgregorosWeb.Components.NotificationItems.OfferNotification do
  @moduledoc """
  Component for rendering an Offer notification.
  Displayed when a user receives a badge offer.
  Includes accept/reject action buttons.
  """
  use EgregorosWeb, :html

  attr :id, :string, required: true
  attr :entry, :map, required: true

  def offer_notification(assigns) do
    assigns =
      assign_new(assigns, :actor_ap_id, fn ->
        Map.get(assigns.entry.actor || %{}, :ap_id)
      end)

    ~H"""
    <article
      id={@id}
      data-role="notification"
      data-type="Offer"
      data-importance="high"
      class="relative border-2 border-[color:var(--border-default)] bg-[color:var(--bg-base)] p-5 transition hover:bg-[color:var(--bg-subtle)]"
    >
      <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div class="flex min-w-0 flex-1 items-start gap-4">
          <.avatar size="sm" name={@entry.actor.display_name} src={@entry.actor.avatar_url} />

          <div class="min-w-0">
            <p class="flex flex-wrap items-center gap-2 text-sm font-semibold text-[color:var(--text-primary)]">
              <.icon name="hero-gift" class="size-4 text-[color:var(--text-muted)]" />
              <span data-role="notification-message" class="truncate">
                {emoji_inline(@entry.message, @entry.message_emojis)}
              </span>
            </p>
            <p class="mt-1 font-mono text-xs text-[color:var(--text-muted)]">
              {@entry.actor.handle}
            </p>

            <%= if is_binary(@actor_ap_id) and @actor_ap_id != "" do %>
              <p
                data-role="offer-issuer-ap-id"
                class="mt-0.5 font-mono text-xs text-[color:var(--text-muted)]"
              >
                {@actor_ap_id}
              </p>
            <% end %>

            <div class="mt-3 flex items-start gap-3">
              <%= if is_binary(@entry[:offer_image_url]) and @entry[:offer_image_url] != "" do %>
                <div class="h-12 w-12 shrink-0 rounded-lg border border-[color:var(--border-default)] bg-[color:var(--bg-subtle)] p-1">
                  <img
                    data-role="offer-badge-image"
                    src={@entry[:offer_image_url]}
                    alt={@entry[:offer_title] || "Badge image"}
                    loading="lazy"
                    class="h-full w-full object-contain"
                  />
                </div>
              <% end %>

              <div class="min-w-0 flex-1">
                <%= if @entry[:offer_title] do %>
                  <p
                    data-role="offer-title"
                    class="text-sm font-semibold text-[color:var(--text-primary)]"
                  >
                    {@entry[:offer_title]}
                  </p>
                <% end %>

                <%= if @entry[:offer_description] do %>
                  <p
                    data-role="offer-description"
                    class="mt-1 text-sm text-[color:var(--text-secondary)]"
                  >
                    {@entry[:offer_description]}
                  </p>
                <% end %>

                <%= if is_binary(@entry[:offer_response]) and @entry[:offer_response] != "" do %>
                  <p
                    data-role="offer-response-status"
                    class="mt-3 text-xs font-semibold uppercase tracking-wide text-[color:var(--text-muted)]"
                  >
                    {@entry[:offer_response]}
                  </p>
                <% else %>
                  <div class="mt-3 flex flex-wrap items-center gap-2">
                    <.button
                      type="button"
                      size="sm"
                      data-role="offer-accept"
                      phx-click="offer_accept"
                      phx-value-id={
                        if(@entry.notification.ap_id,
                          do: @entry.notification.ap_id,
                          else: @entry.notification.id
                        )
                      }
                      phx-disable-with="Accepting..."
                    >
                      Accept
                    </.button>

                    <.button
                      type="button"
                      size="sm"
                      variant="secondary"
                      data-role="offer-reject"
                      phx-click="offer_reject"
                      phx-value-id={
                        if(@entry.notification.ap_id,
                          do: @entry.notification.ap_id,
                          else: @entry.notification.id
                        )
                      }
                      phx-disable-with="Rejecting..."
                    >
                      Reject
                    </.button>
                  </div>
                <% end %>

                <%= if is_binary(@entry[:offer_badge_path]) do %>
                  <.link
                    data-role="offer-badge-link"
                    navigate={@entry[:offer_badge_path]}
                    class="mt-3 inline-flex items-center gap-2 text-xs font-bold uppercase tracking-wide text-[color:var(--link)] hover:text-[color:var(--text-primary)] hover:underline underline-offset-4"
                  >
                    <.icon name="hero-trophy" class="size-4" /> View badge
                  </.link>
                <% end %>
              </div>
            </div>
          </div>
        </div>

        <div class="flex flex-wrap items-center justify-end gap-2">
          <span class="shrink-0 text-xs text-[color:var(--text-muted)]">
            <.time_ago at={@entry.notification.inserted_at} />
          </span>
        </div>
      </div>
    </article>
    """
  end
end
