defmodule EgregorosWeb.Components.TimelineItems.AnnounceCard do
  @moduledoc """
  Component for rendering an Announce (repost/boost) in timelines.

  An Announce wraps another object (typically a Note or Question) and displays it
  with attribution to the user who reposted it. The actual content
  rendering is delegated to NoteCard or PollCard based on the object type.
  """
  use EgregorosWeb, :html

  alias EgregorosWeb.Components.TimelineItems.BadgeCard
  alias EgregorosWeb.Components.TimelineItems.NoteCard
  alias EgregorosWeb.Components.TimelineItems.PollCard

  attr :id, :string, required: true
  attr :entry, :map, required: true
  attr :current_user, :any, default: nil
  attr :back_timeline, :any, default: nil
  attr :reply_mode, :atom, default: :navigate

  @doc """
  Renders an Announce (repost/boost).

  The entry should already be decorated by the StatusVM, which resolves
  the Announce to the underlying object and adds a :reposted_by field
  with the actor who performed the repost.

  Delegates to PollCard for Questions, BadgeCard for badges, NoteCard for everything else.
  """
  def announce_card(assigns) do
    # Check if the underlying object is a Question (poll)
    is_poll? =
      case assigns.entry do
        %{object: %{type: "Question"}} -> true
        %{poll: poll} when not is_nil(poll) -> true
        _ -> false
      end

    is_badge? =
      case assigns.entry do
        %{object: %{type: "VerifiableCredential"}} -> true
        %{badge: %{} = _badge} -> true
        _ -> false
      end

    assigns =
      assigns
      |> assign(:is_poll?, is_poll?)
      |> assign(:is_badge?, is_badge?)

    ~H"""
    <%= cond do %>
      <% @is_poll? -> %>
        <PollCard.poll_card
          id={@id}
          entry={@entry}
          current_user={@current_user}
          back_timeline={@back_timeline}
          reply_mode={@reply_mode}
          show_reposted_by={true}
        />
      <% @is_badge? -> %>
        <BadgeCard.badge_card
          id={@id}
          entry={@entry}
          current_user={@current_user}
          back_timeline={@back_timeline}
          reply_mode={@reply_mode}
          show_reposted_by={true}
        />
      <% true -> %>
        <NoteCard.note_card
          id={@id}
          entry={@entry}
          current_user={@current_user}
          back_timeline={@back_timeline}
          reply_mode={@reply_mode}
          show_reposted_by={true}
        />
    <% end %>
    """
  end
end
