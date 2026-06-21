defmodule EgregorosWeb.Components.TimelineItems.BadgeCard do
  @moduledoc """
  Component for rendering a Badge (VerifiableCredential) in timelines.
  """
  use EgregorosWeb, :html

  alias EgregorosWeb.Components.Shared.ActorHeader
  alias EgregorosWeb.Components.Shared.InteractionBar
  alias EgregorosWeb.ProfilePaths

  attr :id, :string, required: true
  attr :entry, :map, required: true
  attr :current_user, :any, default: nil
  attr :back_timeline, :any, default: nil
  attr :reply_mode, :atom, default: :navigate
  attr :show_reposted_by, :boolean, default: true

  def badge_card(assigns) do
    badge = Map.get(assigns.entry, :badge, %{})

    assigns =
      assign(assigns,
        badge: badge,
        feed_id: feed_id_for_entry(assigns.entry),
        recipient: Map.get(badge, :recipient),
        badge_path: Map.get(badge, :badge_path),
        recipient_path: recipient_path(badge),
        badge_actor: badge_actor(Map.get(assigns.entry, :actor), badge),
        reposted?: Map.get(assigns.entry, :reposted?, false),
        reposts_count: Map.get(assigns.entry, :reposts_count, 0)
      )

    ~H"""
    <article
      id={@id}
      data-role="status-card"
      data-type="VerifiableCredential"
      data-item="badge-card"
      class="scroll-mt-24 border-b border-[color:var(--border-muted)] bg-[color:var(--bg-base)] p-5 transition hover:bg-[color:var(--bg-subtle)] target:ring-2 target:ring-[color:var(--border-default)]"
    >
      <.reposted_by_header
        :if={@show_reposted_by}
        reposted_by={Map.get(@entry, :reposted_by)}
      />

      <div class="flex items-start justify-between gap-3">
        <ActorHeader.actor_header
          actor={@badge_actor}
          object={@entry.object}
          link={false}
        />

        <div class="flex items-center gap-2 text-xs font-bold uppercase tracking-wide text-[color:var(--text-muted)]">
          <.icon name="hero-trophy" class="size-4" /> Badge
        </div>
      </div>

      <div class="mt-4 grid gap-4 lg:grid-cols-[auto,1fr]">
        <div class="flex h-24 w-24 items-center justify-center overflow-hidden border-2 border-[color:var(--border-default)] bg-[color:var(--bg-subtle)]">
          <%= if is_binary(@badge.image_url) and @badge.image_url != "" do %>
            <img
              data-role="badge-image"
              src={@badge.image_url}
              alt={@badge.title || "Badge"}
              class="h-full w-full object-contain"
              loading="lazy"
            />
          <% else %>
            <.icon name="hero-trophy" class="size-8 text-[color:var(--text-muted)]" />
          <% end %>
        </div>

        <div class="min-w-0">
          <h3 data-role="badge-title" class="text-xl font-bold text-[color:var(--text-primary)]">
            {@badge.title || "Badge"}
          </h3>
          <p
            :if={@badge.description}
            data-role="badge-description"
            class="mt-1 text-sm text-[color:var(--text-secondary)]"
          >
            {@badge.description}
          </p>

          <div class="mt-3 flex flex-wrap items-center gap-2 text-xs">
            <span
              data-role="badge-validity"
              class={[
                "inline-flex items-center border px-2 py-1 font-bold uppercase tracking-wide",
                validity_classes(@badge.validity)
              ]}
            >
              {@badge.validity}
            </span>
            <span :if={@badge.valid_range} class="font-mono text-[color:var(--text-muted)]">
              {@badge.valid_range}
            </span>
          </div>

          <div :if={@recipient} class="mt-3 flex flex-wrap items-center gap-2 text-xs">
            <span class="font-mono uppercase tracking-wide text-[color:var(--text-muted)]">
              Awarded to
            </span>
            <%= if is_binary(@recipient_path) do %>
              <.link
                navigate={@recipient_path}
                class="font-semibold text-[color:var(--text-secondary)] hover:text-[color:var(--text-primary)] hover:underline underline-offset-2"
              >
                {@recipient.display_name || @recipient.handle}
              </.link>
            <% else %>
              <span class="font-semibold text-[color:var(--text-secondary)]">
                {@recipient.display_name || @recipient.handle}
              </span>
            <% end %>
          </div>
        </div>
      </div>

      <div class="mt-4 flex flex-wrap items-center gap-2">
        <%= if is_binary(@badge_path) do %>
          <.link
            navigate={@badge_path}
            data-role="badge-view"
            class="inline-flex cursor-pointer items-center gap-2 border-2 border-[color:var(--border-default)] bg-[color:var(--bg-base)] px-3 py-1.5 text-xs font-bold uppercase tracking-wide text-[color:var(--text-primary)] transition hover:bg-[color:var(--bg-muted)]"
          >
            View badge
          </.link>
        <% end %>
      </div>

      <InteractionBar.interaction_bar
        id={@id}
        entry={@entry}
        current_user={@current_user}
        reply_mode={@reply_mode}
      />
    </article>
    """
  end

  attr :reposted_by, :map, default: nil

  defp reposted_by_header(assigns) do
    ~H"""
    <%= if @reposted_by do %>
      <div
        data-role="reposted-by"
        class="mb-3 inline-flex items-center gap-1.5 bg-[color:var(--bg-muted)] py-1 pl-1 pr-2.5 text-xs font-mono text-[color:var(--text-muted)]"
      >
        <.avatar
          size="xs"
          name={@reposted_by.display_name}
          src={@reposted_by.avatar_url}
          class="!h-5 !w-5 !border"
        />
        <.icon name="hero-arrow-path" class="size-3" />
        <%= if is_binary(repost_path = actor_profile_path(@reposted_by)) do %>
          <.link
            navigate={repost_path}
            class="font-semibold text-[color:var(--text-secondary)] hover:text-[color:var(--text-primary)] hover:underline underline-offset-2 focus-visible:outline-none"
          >
            {reposter_short_name(@reposted_by)}
          </.link>
        <% else %>
          <span class="font-semibold text-[color:var(--text-secondary)]">
            {reposter_short_name(@reposted_by)}
          </span>
        <% end %>
        <span>shared</span>
      </div>
    <% end %>
    """
  end

  defp actor_profile_path(actor), do: ProfilePaths.profile_path(actor)

  defp badge_actor(actor, %{issuer_ap_id: issuer_ap_id})
       when is_map(actor) and is_binary(issuer_ap_id) and issuer_ap_id != "" do
    Map.put(actor, :handle, issuer_ap_id)
  end

  defp badge_actor(actor, _badge) when is_map(actor), do: actor
  defp badge_actor(_actor, _badge), do: %{}

  defp reposter_short_name(%{display_name: name}) when is_binary(name) and name != "", do: name

  defp reposter_short_name(%{nickname: nickname}) when is_binary(nickname) and nickname != "" do
    nickname
  end

  defp reposter_short_name(%{handle: handle}) when is_binary(handle) do
    handle
    |> String.trim_leading("@")
    |> String.split("@")
    |> List.first()
  end

  defp reposter_short_name(_), do: "someone"

  defp feed_id_for_entry(%{feed_id: id}) when is_binary(id), do: id
  defp feed_id_for_entry(%{object: %{id: id}}) when is_binary(id), do: id
  defp feed_id_for_entry(%{object: %{"id" => id}}) when is_binary(id), do: id
  defp feed_id_for_entry(_entry), do: nil

  defp recipient_path(%{recipient: recipient}) do
    ProfilePaths.profile_path(recipient)
  end

  defp recipient_path(_badge), do: nil

  defp validity_classes("Expired"),
    do: "border-[color:var(--danger)] bg-[color:var(--bg-base)] text-[color:var(--danger)]"

  defp validity_classes("Not yet valid"),
    do: "border-[color:var(--warning)] bg-[color:var(--bg-base)] text-[color:var(--warning)]"

  defp validity_classes(_status),
    do: "border-[color:var(--success)] bg-[color:var(--bg-base)] text-[color:var(--success)]"
end
