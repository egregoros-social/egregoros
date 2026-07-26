defmodule EgregorosWeb.Components.TimelineItems.NoteCard do
  @moduledoc """
  Component for rendering a Note (standard post/status) in timelines.
  This is the primary content type for microblogging.
  """
  use EgregorosWeb, :html

  alias EgregorosWeb.Components.Shared.ActorHeader
  alias EgregorosWeb.Components.Shared.AttachmentGrid
  alias EgregorosWeb.Components.Shared.ContentBody
  alias EgregorosWeb.Components.Shared.InteractionBar
  alias EgregorosWeb.Components.Shared.StatusMenu
  alias EgregorosWeb.ProfilePaths
  alias EgregorosWeb.URL

  attr :id, :string, required: true
  attr :entry, :map, required: true
  attr :current_user, :any, default: nil
  attr :back_timeline, :any, default: nil
  attr :reply_mode, :atom, default: :navigate
  attr :show_reposted_by, :boolean, default: true

  def note_card(assigns) do
    ~H"""
    <article
      id={@id}
      data-role="status-card"
      data-type="Note"
      class="scroll-mt-24 border-b border-[color:var(--border-muted)] bg-[color:var(--bg-base)] p-5 transition hover:bg-[color:var(--bg-subtle)] target:ring-2 target:ring-[color:var(--border-default)]"
    >
      <.reposted_by_header
        :if={@show_reposted_by}
        reposted_by={Map.get(@entry, :reposted_by)}
      />

      <div class="flex items-start justify-between gap-3">
        <ActorHeader.actor_header
          actor={@entry.actor}
          object={@entry.object}
        />

        <div class="flex items-center gap-2">
          <.permalink_timestamp
            entry={@entry}
            back_timeline={@back_timeline}
          />

          <StatusMenu.status_menu
            card_id={@id}
            entry={@entry}
            current_user={@current_user}
          />
        </div>
      </div>

      <.content_with_warning
        id={@id}
        entry={@entry}
        current_user={@current_user}
      />

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
        <span>reposted</span>
      </div>
    <% end %>
    """
  end

  attr :entry, :map, required: true
  attr :back_timeline, :any, default: nil

  defp permalink_timestamp(assigns) do
    ~H"""
    <%= if is_binary(permalink_path = status_permalink_path(@entry)) do %>
      <.link
        navigate={with_back_timeline(permalink_path, @back_timeline)}
        data-role="post-permalink"
        class="inline-flex hover:underline underline-offset-2 focus-visible:outline-none focus-brutal"
        aria-label="Open post"
      >
        <.time_ago at={object_timestamp(@entry.object)} />
      </.link>
    <% else %>
      <.time_ago at={object_timestamp(@entry.object)} />
    <% end %>
    """
  end

  attr :id, :string, required: true
  attr :entry, :map, required: true
  attr :current_user, :any, default: nil

  defp content_with_warning(assigns) do
    content_warning = ContentBody.content_warning_text(assigns.entry.object)
    assigns = assign(assigns, :content_warning, content_warning)

    ~H"""
    <%= if is_binary(@content_warning) do %>
      <details data-role="content-warning" class="group mt-4">
        <summary class="flex cursor-pointer items-center justify-between gap-4 border-2 border-[color:var(--warning)] bg-[color:var(--warning-subtle)] px-4 py-3 text-left transition hover:bg-[color:var(--bg-subtle)] focus-visible:outline-none focus-brutal list-none [&::-webkit-details-marker]:hidden">
          <div class="flex min-w-0 items-start gap-3">
            <span class="mt-0.5 font-mono text-sm font-bold text-[color:var(--warning)]">
              [CW]
            </span>

            <div class="min-w-0">
              <p class="text-xs font-bold uppercase tracking-wide text-[color:var(--warning)]">
                Content warning
              </p>
              <p
                data-role="content-warning-text"
                class="mt-1 truncate font-medium text-[color:var(--text-primary)]"
                title={@content_warning}
              >
                {@content_warning}
              </p>
            </div>
          </div>

          <span class="inline-flex shrink-0 items-center gap-2 border border-[color:var(--border-default)] bg-[color:var(--bg-base)] px-3 py-1.5 text-xs font-bold uppercase text-[color:var(--text-primary)]">
            <span class="group-open:hidden">Show</span>
            <span class="hidden group-open:inline">Hide</span>
            <.icon name="hero-chevron-down" class="size-4 transition group-open:rotate-180" />
          </span>
        </summary>

        <.note_body id={@id} entry={@entry} current_user={@current_user} />
      </details>
    <% else %>
      <.note_body id={@id} entry={@entry} current_user={@current_user} />
    <% end %>
    """
  end

  attr :id, :string, required: true
  attr :entry, :map, required: true
  attr :current_user, :any, default: nil

  defp note_body(assigns) do
    ~H"""
    <ContentBody.content_body id={@id} object={@entry.object} />

    <AttachmentGrid.attachment_grid
      id={@id}
      attachments={@entry.attachments}
      object={@entry.object}
    />
    """
  end

  # Helper functions

  defp actor_profile_path(actor), do: ProfilePaths.profile_path(actor)

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

  defp with_back_timeline(path, nil) when is_binary(path), do: path

  defp with_back_timeline(path, back_timeline) when is_binary(path) do
    timeline =
      back_timeline
      |> to_string()
      |> String.trim()
      |> String.downcase()

    if timeline in ["home", "public"] do
      delimiter = if String.contains?(path, "?"), do: "&", else: "?"
      path <> delimiter <> "back_timeline=" <> URI.encode_www_form(timeline)
    else
      path
    end
  end

  defp with_back_timeline(path, _back_timeline) when is_binary(path), do: path

  defp status_permalink_path(%{object: %{local: true} = object, actor: %{nickname: nickname}})
       when is_binary(nickname) and nickname != "" do
    case URL.local_object_uuid(Map.get(object, :ap_id)) do
      uuid when is_binary(uuid) and uuid != "" -> "/@#{nickname}/#{uuid}"
      _ -> nil
    end
  end

  defp status_permalink_path(%{object: %{id: id, local: false}, actor: actor})
       when is_binary(id) do
    case ProfilePaths.profile_path(actor) do
      "/@" <> _rest = profile_path -> profile_path <> "/" <> id
      _ -> nil
    end
  end

  defp status_permalink_path(_entry), do: nil

  defp object_timestamp(%{published: %DateTime{} = dt}), do: dt
  defp object_timestamp(%{published: %NaiveDateTime{} = dt}), do: dt

  defp object_timestamp(%{data: %{"published" => published}}) when is_binary(published) do
    case DateTime.from_iso8601(published) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp object_timestamp(%{inserted_at: %DateTime{} = dt}), do: dt
  defp object_timestamp(%{inserted_at: %NaiveDateTime{} = dt}), do: dt
  defp object_timestamp(_), do: nil
end
