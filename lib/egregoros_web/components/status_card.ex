defmodule EgregorosWeb.StatusCard do
  @moduledoc """
  Dispatcher component that routes timeline entries to the appropriate
  type-specific component based on the object type.

  This allows new object types to be added by creating a new component
  module and adding a clause to the render function.
  """
  use EgregorosWeb, :html

  alias EgregorosWeb.Components.TimelineItems.AnnounceCard
  alias EgregorosWeb.Components.TimelineItems.BadgeCard
  alias EgregorosWeb.Components.TimelineItems.NoteCard
  alias EgregorosWeb.Components.TimelineItems.PollCard

  attr :id, :string, required: true
  attr :entry, :map, required: true
  attr :current_user, :any, default: nil
  attr :back_timeline, :any, default: nil
  attr :reply_mode, :atom, default: :navigate

  @doc """
  Renders a status card by dispatching to the appropriate component
  based on the object type.

  ## Supported Types

  - `Note` - Standard microblog post (rendered by NoteCard)
  - `Announce` - Repost/boost (rendered by AnnounceCard, which wraps NoteCard)
  - `Question` - Poll (rendered by PollCard)
  - `VerifiableCredential` - Badge (rendered by BadgeCard)

  ## Examples

      <StatusCard.status_card
        id="post-123"
        entry={entry}
        current_user={@current_user}
        back_timeline={:home}
        reply_mode={:modal}
      />
  """
  def status_card(assigns) do
    ~H"""
    <%= case object_type(@entry) do %>
      <% "Note" -> %>
        <NoteCard.note_card
          id={@id}
          entry={@entry}
          current_user={@current_user}
          back_timeline={@back_timeline}
          reply_mode={@reply_mode}
        />
      <% "Announce" -> %>
        <AnnounceCard.announce_card
          id={@id}
          entry={@entry}
          current_user={@current_user}
          back_timeline={@back_timeline}
          reply_mode={@reply_mode}
        />
      <% "Question" -> %>
        <PollCard.poll_card
          id={@id}
          entry={@entry}
          current_user={@current_user}
          back_timeline={@back_timeline}
          reply_mode={@reply_mode}
        />
      <% "VerifiableCredential" -> %>
        <BadgeCard.badge_card
          id={@id}
          entry={@entry}
          current_user={@current_user}
          back_timeline={@back_timeline}
          reply_mode={@reply_mode}
        />
      <% _unknown -> %>
        <.fallback_card id={@id} entry={@entry} />
    <% end %>
    """
  end

  attr :id, :string, required: true
  attr :entry, :map, required: true

  defp fallback_card(assigns) do
    ~H"""
    <article
      id={@id}
      data-role="status-card"
      data-type="unknown"
      class="border-b border-[color:var(--border-muted)] bg-[color:var(--bg-base)] p-5"
    >
      <div class="flex items-center gap-2 text-sm text-[color:var(--text-muted)]">
        <.icon name="hero-question-mark-circle" class="size-5" />
        <span>Unsupported content type: {object_type(@entry)}</span>
      </div>
    </article>
    """
  end

  # For Announces that have been decorated, the entry might have :reposted_by
  # which indicates it's an Announce even though the object is a Note
  defp object_type(%{reposted_by: %{}} = _entry), do: "Announce"
  defp object_type(%{object: %{type: type}}) when is_binary(type), do: type
  defp object_type(%{object: %{"type" => type}}) when is_binary(type), do: type
  defp object_type(_entry), do: "unknown"
end
