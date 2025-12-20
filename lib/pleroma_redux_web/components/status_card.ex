defmodule PleromaReduxWeb.StatusCard do
  use PleromaReduxWeb, :html

  alias PleromaRedux.HTML
  alias PleromaReduxWeb.ViewModels.Status, as: StatusVM

  attr :id, :string, required: true
  attr :entry, :map, required: true
  attr :current_user, :any, default: nil

  def status_card(assigns) do
    ~H"""
    <article
      id={@id}
      data-role="status-card"
      class="rounded-3xl border border-white/80 bg-white/80 p-6 shadow-lg shadow-slate-200/30 backdrop-blur transition hover:-translate-y-0.5 hover:shadow-xl dark:border-slate-700/60 dark:bg-slate-900/70 dark:shadow-slate-900/50 animate-rise"
    >
      <div class="flex items-start gap-4">
        <div class="shrink-0">
          <%= if is_binary(@entry.actor.avatar_url) and @entry.actor.avatar_url != "" do %>
            <img
              src={@entry.actor.avatar_url}
              alt={@entry.actor.display_name}
              class="h-12 w-12 rounded-2xl border border-slate-200/80 bg-white object-cover shadow-sm shadow-slate-200/40 dark:border-slate-700/60 dark:bg-slate-950/60 dark:shadow-slate-900/40"
              loading="lazy"
            />
          <% else %>
            <div class="flex h-12 w-12 items-center justify-center rounded-2xl border border-slate-200/80 bg-white/70 text-sm font-semibold text-slate-700 shadow-sm shadow-slate-200/30 dark:border-slate-700/60 dark:bg-slate-950/60 dark:text-slate-200 dark:shadow-slate-900/40">
              {avatar_initial(@entry.actor.display_name)}
            </div>
          <% end %>
        </div>

        <div class="min-w-0 flex-1">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p
                data-role="post-actor-name"
                class="truncate text-sm font-semibold text-slate-900 dark:text-slate-100"
              >
                {@entry.actor.display_name}
              </p>
              <div class="mt-1 flex flex-wrap items-center gap-2">
                <span
                  data-role="post-actor-handle"
                  class="truncate text-xs text-slate-500 dark:text-slate-400"
                >
                  {@entry.actor.handle}
                </span>

                <span class="text-[10px] uppercase tracking-[0.25em] text-slate-400 dark:text-slate-500">
                  {if @entry.object.local, do: "local", else: "remote"}
                </span>
              </div>
            </div>

            <span class="text-xs text-slate-400 dark:text-slate-500">
              {format_time(@entry.object.inserted_at)}
            </span>
          </div>

          <div class="mt-3 text-base leading-relaxed text-slate-900 dark:text-slate-100">
            {post_content_html(@entry.object)}
          </div>

          <div
            :if={@entry.attachments != []}
            data-role="attachments"
            class="mt-4 grid gap-3 sm:grid-cols-2"
          >
            <div
              :for={attachment <- @entry.attachments}
              class="group overflow-hidden rounded-2xl border border-slate-200/80 bg-white shadow-sm shadow-slate-200/20 dark:border-slate-700/70 dark:bg-slate-950/60 dark:shadow-slate-900/40"
            >
              <.attachment_media attachment={attachment} />
            </div>
          </div>
        </div>
      </div>

      <div :if={@current_user} class="mt-5 flex flex-wrap items-center gap-3">
        <button
          type="button"
          data-role="like"
          phx-click="toggle_like"
          phx-value-id={@entry.object.id}
          phx-disable-with="..."
          aria-pressed={@entry.liked?}
          class={[
            "inline-flex items-center gap-2 rounded-full border px-4 py-2 text-sm font-semibold transition hover:-translate-y-0.5",
            @entry.liked? &&
              "border-rose-200/70 bg-rose-50/80 text-rose-700 hover:bg-rose-50 dark:border-rose-500/30 dark:bg-rose-500/10 dark:text-rose-200 dark:hover:bg-rose-500/10",
            !@entry.liked? &&
              "border-slate-200/80 bg-white/70 text-slate-700 hover:bg-white dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:hover:bg-slate-950"
          ]}
        >
          <.icon name={if @entry.liked?, do: "hero-heart-solid", else: "hero-heart"} class="size-4" />
          {if @entry.liked?, do: "Unlike", else: "Like"}
          <span class="text-xs font-normal text-slate-500 dark:text-slate-400">
            {@entry.likes_count}
          </span>
        </button>

        <button
          type="button"
          data-role="repost"
          phx-click="toggle_repost"
          phx-value-id={@entry.object.id}
          phx-disable-with="..."
          aria-pressed={@entry.reposted?}
          class={[
            "inline-flex items-center gap-2 rounded-full border px-4 py-2 text-sm font-semibold transition hover:-translate-y-0.5",
            @entry.reposted? &&
              "border-emerald-200/70 bg-emerald-50/80 text-emerald-700 hover:bg-emerald-50 dark:border-emerald-500/30 dark:bg-emerald-500/10 dark:text-emerald-200 dark:hover:bg-emerald-500/10",
            !@entry.reposted? &&
              "border-slate-200/80 bg-white/70 text-slate-700 hover:bg-white dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:hover:bg-slate-950"
          ]}
        >
          <.icon
            name={if @entry.reposted?, do: "hero-arrow-path-solid", else: "hero-arrow-path"}
            class="size-4"
          />
          {if @entry.reposted?, do: "Unrepost", else: "Repost"}
          <span class="text-xs font-normal text-slate-500 dark:text-slate-400">
            {@entry.reposts_count}
          </span>
        </button>

        <div class="flex flex-wrap items-center gap-2">
          <%= for emoji <- StatusVM.reaction_emojis() do %>
            <% reaction = Map.get(@entry.reactions, emoji, %{count: 0, reacted?: false}) %>

            <button
              type="button"
              data-role="reaction"
              data-emoji={emoji}
              phx-click="toggle_reaction"
              phx-value-id={@entry.object.id}
              phx-value-emoji={emoji}
              phx-disable-with="..."
              aria-pressed={reaction.reacted?}
              class={[
                "inline-flex items-center gap-2 rounded-full border px-3 py-2 text-sm font-semibold transition hover:-translate-y-0.5",
                reaction.reacted? &&
                  "border-emerald-200/70 bg-emerald-50/80 text-emerald-700 hover:bg-emerald-50 dark:border-emerald-500/30 dark:bg-emerald-500/10 dark:text-emerald-200 dark:hover:bg-emerald-500/10",
                !reaction.reacted? &&
                  "border-slate-200/80 bg-white/70 text-slate-700 hover:bg-white dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:hover:bg-slate-950"
              ]}
            >
              <span class="text-base leading-none">{emoji}</span>
              <span class="text-xs font-normal">{reaction.count}</span>
            </button>
          <% end %>
        </div>
      </div>
    </article>
    """
  end

  defp post_content_html(%{data: %{} = data} = object) do
    raw = Map.get(data, "content", "")

    format =
      case Map.get(object, :local) do
        false -> :html
        _ -> :text
      end

    raw
    |> HTML.to_safe_html(format: format)
    |> Phoenix.HTML.raw()
  end

  defp post_content_html(_object), do: ""

  defp format_time(%DateTime{} = dt) do
    dt
    |> DateTime.to_naive()
    |> NaiveDateTime.truncate(:second)
    |> NaiveDateTime.to_string()
  end

  defp format_time(%NaiveDateTime{} = dt) do
    dt
    |> NaiveDateTime.truncate(:second)
    |> NaiveDateTime.to_string()
  end

  defp format_time(_), do: ""

  defp avatar_initial(name) when is_binary(name) do
    name = String.trim(name)

    case String.first(name) do
      nil -> "?"
      letter -> String.upcase(letter)
    end
  end

  defp avatar_initial(_), do: "?"

  attr :attachment, :map, required: true

  defp attachment_media(assigns) do
    ~H"""
    <%= case attachment_kind(@attachment) do %>
      <% :image -> %>
        <img
          data-role="attachment"
          data-kind="image"
          src={@attachment.href}
          alt={@attachment.description}
          class="h-44 w-full object-cover transition duration-300 group-hover:scale-[1.02]"
          loading="lazy"
        />
      <% :video -> %>
        <video
          data-role="attachment"
          data-kind="video"
          class="h-44 w-full bg-black object-cover transition duration-300 group-hover:scale-[1.02]"
          controls
          preload="metadata"
          playsinline
          aria-label={attachment_label(@attachment, "Video attachment")}
        >
          <source src={@attachment.href} type={attachment_source_type(@attachment, "video/mp4")} />
        </video>
      <% :audio -> %>
        <div class="flex h-44 w-full items-center px-4">
          <audio
            data-role="attachment"
            data-kind="audio"
            controls
            class="w-full"
            preload="metadata"
            aria-label={attachment_label(@attachment, "Audio attachment")}
          >
            <source src={@attachment.href} type={attachment_source_type(@attachment, "audio/mpeg")} />
          </audio>
        </div>
      <% :link -> %>
        <a
          data-role="attachment"
          data-kind="link"
          href={@attachment.href}
          target="_blank"
          rel="noreferrer noopener"
          class="flex h-44 w-full items-center justify-center gap-3 px-4 text-sm font-semibold text-slate-700 transition hover:bg-slate-50/80 dark:text-slate-200 dark:hover:bg-white/5"
          title={attachment_link_label(@attachment)}
        >
          <.icon name="hero-arrow-down-tray" class="size-5 text-slate-500 dark:text-slate-400" />
          <span class="truncate">{attachment_link_label(@attachment)}</span>
        </a>
    <% end %>
    """
  end

  defp attachment_kind(%{media_type: media_type})
       when is_binary(media_type) and media_type != "" do
    cond do
      String.starts_with?(media_type, "image/") -> :image
      String.starts_with?(media_type, "video/") -> :video
      String.starts_with?(media_type, "audio/") -> :audio
      true -> :link
    end
  end

  defp attachment_kind(%{href: href}) when is_binary(href) and href != "" do
    ext =
      href
      |> URI.parse()
      |> then(fn
        %URI{path: path} when is_binary(path) -> Path.extname(path)
        _ -> Path.extname(href)
      end)
      |> String.downcase()

    cond do
      ext in ~w(.apng .avif .bmp .gif .heic .heif .jpeg .jpg .png .svg .webp) -> :image
      ext in ~w(.m4v .mov .mp4 .ogv .webm) -> :video
      ext in ~w(.aac .flac .m4a .mp3 .ogg .opus .wav) -> :audio
      true -> :link
    end
  end

  defp attachment_kind(_), do: :link

  defp attachment_source_type(%{media_type: media_type}, _fallback)
       when is_binary(media_type) and media_type != "" do
    media_type
  end

  defp attachment_source_type(_attachment, fallback), do: fallback

  defp attachment_label(%{description: description}, fallback) when is_binary(description) do
    description = String.trim(description)
    if description == "", do: fallback, else: description
  end

  defp attachment_label(_attachment, fallback), do: fallback

  defp attachment_link_label(%{description: description} = attachment)
       when is_binary(description) do
    description = String.trim(description)
    if description == "", do: attachment_filename(attachment), else: description
  end

  defp attachment_link_label(attachment), do: attachment_filename(attachment)

  defp attachment_filename(%{href: href}) when is_binary(href) and href != "" do
    case URI.parse(href) do
      %URI{path: path} when is_binary(path) and path != "" ->
        path
        |> String.split("/", trim: true)
        |> List.last()
        |> case do
          nil -> href
          value -> value
        end

      _ ->
        href
    end
  end

  defp attachment_filename(_), do: "Attachment"
end
