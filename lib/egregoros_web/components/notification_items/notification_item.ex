defmodule EgregorosWeb.Components.NotificationItems.NotificationItem do
  @moduledoc """
  Dispatcher component that routes notification entries to the appropriate
  type-specific component based on the notification type.
  """
  use EgregorosWeb, :html

  alias EgregorosWeb.Components.NotificationItems.FollowNotification
  alias EgregorosWeb.Components.NotificationItems.LikeNotification
  alias EgregorosWeb.Components.NotificationItems.MentionNotification
  alias EgregorosWeb.Components.NotificationItems.OfferNotification
  alias EgregorosWeb.Components.NotificationItems.ReactionNotification
  alias EgregorosWeb.Components.NotificationItems.RepostNotification

  attr :id, :string, required: true
  attr :entry, :map, required: true

  @doc """
  Renders a notification item by dispatching to the appropriate component
  based on the notification type.

  ## Supported Types

  - `Follow` - New follower notification
  - `Like` - Someone liked your post
  - `Announce` - Someone reposted your post
  - `EmojiReact` - Someone reacted to your post
  - `Note` - Someone mentioned you
  - `Offer` - A badge offer

  ## Examples

      <NotificationItem.notification_item
        id="notification-123"
        entry={entry}
      />
  """
  def notification_item(assigns) do
    ~H"""
    <%= case @entry.type do %>
      <% "Follow" -> %>
        <FollowNotification.follow_notification id={@id} entry={@entry} />
      <% "Like" -> %>
        <LikeNotification.like_notification id={@id} entry={@entry} />
      <% "Announce" -> %>
        <RepostNotification.repost_notification id={@id} entry={@entry} />
      <% "EmojiReact" -> %>
        <ReactionNotification.reaction_notification id={@id} entry={@entry} />
      <% "Note" -> %>
        <MentionNotification.mention_notification id={@id} entry={@entry} />
      <% "Offer" -> %>
        <OfferNotification.offer_notification id={@id} entry={@entry} />
      <% _unknown -> %>
        <.fallback_notification id={@id} entry={@entry} />
    <% end %>
    """
  end

  attr :id, :string, required: true
  attr :entry, :map, required: true

  defp fallback_notification(assigns) do
    ~H"""
    <article
      id={@id}
      data-role="notification"
      data-type={@entry.type}
      data-importance="medium"
      class="relative border border-[color:var(--border-muted)] bg-[color:var(--bg-base)] p-5 transition hover:bg-[color:var(--bg-subtle)]"
    >
      <div class="flex items-start gap-3 pl-2">
        <div data-role="notification-avatar">
          <.avatar
            size="sm"
            name={@entry.actor.display_name}
            src={@entry.actor.avatar_url}
          />
        </div>

        <div class="min-w-0 flex-1 space-y-3">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p class="flex flex-wrap items-center gap-2 text-sm font-semibold text-[color:var(--text-primary)]">
                <.icon name="hero-bell" class="size-4 text-[color:var(--text-muted)]" />
                <span data-role="notification-message" class="truncate">
                  {emoji_inline(@entry.message, @entry.message_emojis)}
                </span>
              </p>
              <p class="mt-1 font-mono text-xs text-[color:var(--text-muted)]">
                {@entry.actor.handle}
              </p>
            </div>

            <span class="shrink-0">
              <.time_ago at={@entry.notification.inserted_at} />
            </span>
          </div>
        </div>
      </div>
    </article>
    """
  end
end
