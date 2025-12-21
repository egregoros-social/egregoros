defmodule PleromaReduxWeb.StatusCard do
  use PleromaReduxWeb, :html

  alias PleromaRedux.HTML
  alias PleromaReduxWeb.ProfilePaths
  alias PleromaReduxWeb.URL
  alias PleromaReduxWeb.ViewModels.Status, as: StatusVM

  @content_collapse_threshold 500

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
      <div class="flex items-start justify-between gap-3">
        <div class="flex min-w-0 items-start gap-4">
          <%= if is_binary(profile_path = actor_profile_path(@entry.actor)) do %>
            <.link
              navigate={profile_path}
              data-role="actor-link"
              class="group flex min-w-0 items-start gap-4 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400"
            >
              <div class="shrink-0">
                <.actor_avatar actor={@entry.actor} />
              </div>

              <div class="min-w-0">
                <p
                  data-role="post-actor-name"
                  class="truncate text-sm font-semibold text-slate-900 transition group-hover:underline dark:text-slate-100"
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
            </.link>
          <% else %>
            <div class="shrink-0">
              <.actor_avatar actor={@entry.actor} />
            </div>

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
          <% end %>
        </div>

        <div class="flex items-center gap-2">
          <%= if is_binary(permalink_path = status_permalink_path(@entry)) do %>
            <.link
              navigate={permalink_path}
              data-role="post-permalink"
              class="inline-flex focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400"
              aria-label="Open post"
            >
              <.time_ago at={@entry.object.inserted_at} />
            </.link>
          <% else %>
            <.time_ago at={@entry.object.inserted_at} />
          <% end %>

          <.status_menu entry={@entry} />
        </div>
      </div>

      <% content_warning = content_warning_text(@entry.object) %>

      <%= if is_binary(content_warning) do %>
        <details data-role="content-warning" class="group mt-3">
          <summary class="flex cursor-pointer items-center justify-between gap-4 rounded-2xl border border-amber-200/80 bg-amber-50/50 px-4 py-3 text-left text-slate-900 transition hover:bg-amber-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400 dark:border-amber-400/20 dark:bg-amber-400/10 dark:text-slate-100 dark:hover:bg-amber-400/15 list-none [&::-webkit-details-marker]:hidden">
            <div class="flex min-w-0 items-start gap-3">
              <span class="mt-0.5 inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-xl bg-amber-100 text-amber-700 dark:bg-amber-400/15 dark:text-amber-200">
                <.icon name="hero-exclamation-triangle" class="size-4" />
              </span>

              <div class="min-w-0">
                <p class="text-[10px] font-semibold uppercase tracking-[0.25em] text-amber-700 dark:text-amber-200">
                  Content warning
                </p>
                <p
                  data-role="content-warning-text"
                  class="mt-1 truncate text-sm font-semibold text-slate-900 dark:text-slate-100"
                  title={content_warning}
                >
                  {content_warning}
                </p>
              </div>
            </div>

            <span class="inline-flex shrink-0 items-center gap-2 rounded-xl bg-white/80 px-3 py-2 text-xs font-semibold text-slate-700 shadow-sm shadow-slate-200/20 transition group-open:bg-white dark:bg-slate-950/60 dark:text-slate-200 dark:shadow-slate-900/30 dark:group-open:bg-slate-950">
              <span class="group-open:hidden">Show</span>
              <span class="hidden group-open:inline">Hide</span>
              <.icon name="hero-chevron-down" class="size-4 transition group-open:rotate-180" />
            </span>
          </summary>

          <.status_body entry={@entry} />
        </details>
      <% else %>
        <.status_body entry={@entry} />
      <% end %>

      <div :if={@current_user} class="mt-5 flex flex-wrap items-center gap-3">
        <%= if is_binary(reply_path = status_reply_path(@entry)) do %>
          <.link
            navigate={reply_path}
            data-role="reply"
            class="inline-flex items-center gap-2 rounded-full border border-slate-200/80 bg-white/70 px-4 py-2 text-sm font-semibold text-slate-700 shadow-sm shadow-slate-200/20 transition hover:-translate-y-0.5 hover:bg-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:shadow-slate-900/40 dark:hover:bg-slate-950"
          >
            <.icon name="hero-chat-bubble-left-right" class="size-4" /> Reply
          </.link>
        <% end %>

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

  attr :entry, :map, required: true

  defp status_body(assigns) do
    ~H"""
    <% sensitive_media = sensitive_media?(@entry.object) %>
    <% collapsible_content = long_content?(@entry.object) %>
    <% content_id = "post-content-#{@entry.object.id}" %>
    <% fade_id = "#{content_id}-fade" %>
    <% toggle_more_id = "#{content_id}-more" %>
    <% toggle_less_id = "#{content_id}-less" %>
    <% toggle_icon_id = "#{content_id}-icon" %>

    <div
      id={content_id}
      data-role="post-content"
      class={[
        "mt-3 text-base leading-relaxed text-slate-900 dark:text-slate-100",
        collapsible_content && "relative max-h-64 overflow-hidden"
      ]}
    >
      {post_content_html(@entry.object)}

      <div
        :if={collapsible_content}
        id={fade_id}
        class="pointer-events-none absolute inset-x-0 bottom-0 h-20 bg-gradient-to-t from-white/95 to-transparent dark:from-slate-900/85"
        aria-hidden="true"
      >
      </div>
    </div>

    <button
      :if={collapsible_content}
      type="button"
      data-role="post-content-toggle"
      aria-controls={content_id}
      aria-expanded="false"
      phx-click={
        JS.toggle_class("max-h-64 overflow-hidden", to: "##{content_id}")
        |> JS.toggle_class("hidden", to: "##{fade_id}")
        |> JS.toggle_class("hidden", to: "##{toggle_more_id}")
        |> JS.toggle_class("hidden", to: "##{toggle_less_id}")
        |> JS.toggle_class("rotate-180", to: "##{toggle_icon_id}")
        |> JS.toggle_attribute({"aria-expanded", "true", "false"})
      }
      class="mt-2 inline-flex items-center gap-2 rounded-full bg-slate-900/5 px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-slate-700 transition hover:bg-slate-900/10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:bg-white/5 dark:text-slate-200 dark:hover:bg-white/10"
    >
      <span id={toggle_more_id}>Show more</span>
      <span id={toggle_less_id} class="hidden">Show less</span>
      <span id={toggle_icon_id} class="inline-flex">
        <.icon name="hero-chevron-down" class="size-4 transition" />
      </span>
    </button>

    <div
      :if={sensitive_media and @entry.attachments != []}
      id={"sensitive-media-#{@entry.object.id}"}
      data-role="sensitive-media"
      class="mt-4 flex items-center justify-between gap-4 rounded-2xl border border-rose-200/70 bg-rose-50/70 px-4 py-3 dark:border-rose-500/20 dark:bg-rose-500/10"
    >
      <div class="flex min-w-0 items-center gap-3">
        <span class="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-rose-100 text-rose-700 dark:bg-rose-500/15 dark:text-rose-200">
          <.icon name="hero-eye-slash" class="size-4" />
        </span>

        <div class="min-w-0">
          <p class="text-sm font-semibold text-slate-900 dark:text-slate-100">Sensitive media</p>
          <p class="mt-0.5 text-xs text-slate-600 dark:text-slate-300">Hidden by default.</p>
        </div>
      </div>

      <button
        type="button"
        data-role="sensitive-media-reveal"
        phx-click={
          JS.hide(to: "#sensitive-media-#{@entry.object.id}")
          |> JS.remove_class("hidden", to: "#attachments-#{@entry.object.id}")
        }
        class="inline-flex items-center gap-2 rounded-xl bg-slate-900 px-4 py-2 text-xs font-semibold text-white shadow-sm shadow-slate-900/20 transition hover:-translate-y-0.5 hover:bg-slate-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-rose-400 dark:bg-white dark:text-slate-900 dark:shadow-slate-900/40 dark:hover:bg-slate-100"
      >
        <.icon name="hero-eye" class="size-4" /> Reveal
      </button>
    </div>

    <div
      :if={@entry.attachments != []}
      id={"attachments-#{@entry.object.id}"}
      data-role="attachments"
      class={[
        "mt-4 grid gap-3 sm:grid-cols-2",
        sensitive_media && "hidden"
      ]}
    >
      <div
        :for={{attachment, index} <- Enum.with_index(@entry.attachments)}
        class="group overflow-hidden rounded-2xl border border-slate-200/80 bg-white shadow-sm shadow-slate-200/20 dark:border-slate-700/70 dark:bg-slate-950/60 dark:shadow-slate-900/40"
      >
        <.attachment_media attachment={attachment} post_id={@entry.object.id} index={index} />
      </div>
    </div>
    """
  end

  defp long_content?(%{data: %{} = data} = object) do
    raw =
      data
      |> Map.get("content", "")
      |> to_string()
      |> String.trim()

    text =
      cond do
        raw == "" ->
          ""

        Map.get(object, :local) ->
          raw

        looks_like_html?(raw) ->
          case FastSanitize.strip_tags(raw) do
            {:ok, stripped} -> stripped
            _ -> raw
          end

        true ->
          raw
      end

    String.length(String.trim(text)) > @content_collapse_threshold
  end

  defp long_content?(_object), do: false

  defp looks_like_html?(content) when is_binary(content) do
    String.contains?(content, "<") and String.contains?(content, ">")
  end

  defp looks_like_html?(_content), do: false

  defp sensitive_media?(%{data: %{} = data}) do
    data
    |> Map.get("sensitive", false)
    |> case do
      true -> true
      "true" -> true
      _ -> false
    end
  end

  defp sensitive_media?(_object), do: false

  defp content_warning_text(%{data: %{} = data}) do
    case Map.get(data, "summary") do
      summary when is_binary(summary) ->
        summary = String.trim(summary)
        if summary == "", do: nil, else: summary

      _ ->
        nil
    end
  end

  defp content_warning_text(_object), do: nil

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

  defp avatar_initial(name) when is_binary(name) do
    name = String.trim(name)

    case String.first(name) do
      nil -> "?"
      letter -> String.upcase(letter)
    end
  end

  defp avatar_initial(_), do: "?"

  defp actor_profile_path(actor), do: ProfilePaths.profile_path(actor)

  defp status_permalink_path(%{object: %{local: true} = object, actor: %{nickname: nickname}})
       when is_binary(nickname) and nickname != "" do
    case URL.local_object_uuid(Map.get(object, :ap_id)) do
      uuid when is_binary(uuid) and uuid != "" -> "/@#{nickname}/#{uuid}"
      _ -> nil
    end
  end

  defp status_permalink_path(_entry), do: nil

  defp status_reply_path(entry) do
    case status_permalink_path(entry) do
      path when is_binary(path) and path != "" -> path <> "?reply=true#reply-form"
      _ -> nil
    end
  end

  defp status_share_url(entry) when is_map(entry) do
    object = Map.get(entry, :object) || %{}
    ap_id = Map.get(object, :ap_id) || Map.get(object, "ap_id")

    cond do
      is_binary(path = status_permalink_path(entry)) and path != "" ->
        URL.absolute(path)

      is_binary(ap_id) and ap_id != "" ->
        if safe_http_url?(ap_id), do: ap_id, else: nil

      true ->
        nil
    end
  end

  defp safe_http_url?(url) when is_binary(url) do
    case URI.parse(String.trim(url)) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        true

      _ ->
        false
    end
  end

  defp safe_http_url?(_url), do: false

  attr :entry, :map, required: true

  defp status_menu(assigns) do
    assigns = assign(assigns, :share_url, status_share_url(assigns.entry))

    ~H"""
    <details data-role="status-menu" class="relative">
      <summary class="list-none [&::-webkit-details-marker]:hidden">
        <span class="inline-flex h-9 w-9 items-center justify-center rounded-2xl text-slate-500 transition hover:bg-slate-900/5 hover:text-slate-900 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:text-slate-300 dark:hover:bg-white/10 dark:hover:text-white">
          <.icon name="hero-ellipsis-horizontal" class="size-5" />
        </span>
      </summary>

      <div class="absolute right-0 top-10 z-40 w-48 overflow-hidden rounded-2xl border border-slate-200/80 bg-white/95 shadow-xl shadow-slate-900/10 backdrop-blur dark:border-slate-700/70 dark:bg-slate-950/80 dark:shadow-slate-900/40">
        <button
          :if={is_binary(@share_url) and @share_url != ""}
          type="button"
          data-role="copy-link"
          data-copy-text={@share_url}
          phx-click={JS.dispatch("predux:copy") |> JS.push("copied_link")}
          class="flex w-full items-center gap-3 px-4 py-3 text-sm font-semibold text-slate-700 transition hover:bg-slate-900/5 dark:text-slate-200 dark:hover:bg-white/10"
        >
          <.icon name="hero-clipboard-document" class="size-5 text-slate-500 dark:text-slate-400" />
          Copy link
        </button>

        <a
          :if={is_binary(@share_url) and @share_url != ""}
          data-role="open-link"
          href={@share_url}
          target="_blank"
          rel="noreferrer noopener"
          class="flex items-center gap-3 px-4 py-3 text-sm font-semibold text-slate-700 transition hover:bg-slate-900/5 dark:text-slate-200 dark:hover:bg-white/10"
        >
          <.icon
            name="hero-arrow-top-right-on-square"
            class="size-5 text-slate-500 dark:text-slate-400"
          /> Open link
        </a>
      </div>
    </details>
    """
  end

  attr :actor, :map, required: true

  defp actor_avatar(assigns) do
    ~H"""
    <%= if is_binary(@actor.avatar_url) and @actor.avatar_url != "" do %>
      <img
        src={@actor.avatar_url}
        alt={@actor.display_name}
        class="h-12 w-12 rounded-2xl border border-slate-200/80 bg-white object-cover shadow-sm shadow-slate-200/40 dark:border-slate-700/60 dark:bg-slate-950/60 dark:shadow-slate-900/40"
        loading="lazy"
      />
    <% else %>
      <div class="flex h-12 w-12 items-center justify-center rounded-2xl border border-slate-200/80 bg-white/70 text-sm font-semibold text-slate-700 shadow-sm shadow-slate-200/30 dark:border-slate-700/60 dark:bg-slate-950/60 dark:text-slate-200 dark:shadow-slate-900/40">
        {avatar_initial(@actor.display_name)}
      </div>
    <% end %>
    """
  end

  attr :attachment, :map, required: true
  attr :post_id, :any, required: true
  attr :index, :integer, required: true

  defp attachment_media(assigns) do
    ~H"""
    <%= case PleromaReduxWeb.Attachments.kind(@attachment) do %>
      <% :image -> %>
        <button
          type="button"
          data-role="attachment-open"
          data-index={@index}
          phx-click="open_media"
          phx-value-id={@post_id}
          phx-value-index={@index}
          class="block w-full text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400"
          aria-label={attachment_label(@attachment, "Open image")}
        >
          <img
            data-role="attachment"
            data-kind="image"
            src={@attachment.href}
            alt={@attachment.description}
            class="h-44 w-full object-cover transition duration-300 group-hover:scale-[1.02]"
            loading="lazy"
          />
        </button>
      <% :video -> %>
        <div class="group relative">
          <video
            data-role="attachment"
            data-kind="video"
            class="h-44 w-full bg-black object-cover transition duration-300 group-hover:scale-[1.02]"
            controls
            preload="metadata"
            playsinline
            aria-label={attachment_label(@attachment, "Video attachment")}
          >
            <source
              src={@attachment.href}
              type={PleromaReduxWeb.Attachments.source_type(@attachment, "video/mp4")}
            />
          </video>

          <button
            type="button"
            data-role="attachment-open"
            data-index={@index}
            phx-click="open_media"
            phx-value-id={@post_id}
            phx-value-index={@index}
            class="absolute right-3 top-3 inline-flex h-9 w-9 items-center justify-center rounded-2xl bg-white/10 text-white transition hover:bg-white/20 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/60"
            aria-label={attachment_label(@attachment, "Open video")}
          >
            <.icon name="hero-arrows-pointing-out" class="size-4" />
          </button>
        </div>
      <% :audio -> %>
        <div class="group relative flex h-44 w-full items-center px-4">
          <audio
            data-role="attachment"
            data-kind="audio"
            controls
            class="w-full"
            preload="metadata"
            aria-label={attachment_label(@attachment, "Audio attachment")}
          >
            <source
              src={@attachment.href}
              type={PleromaReduxWeb.Attachments.source_type(@attachment, "audio/mpeg")}
            />
          </audio>

          <button
            type="button"
            data-role="attachment-open"
            data-index={@index}
            phx-click="open_media"
            phx-value-id={@post_id}
            phx-value-index={@index}
            class="absolute right-3 top-3 inline-flex h-9 w-9 items-center justify-center rounded-2xl bg-white/10 text-white transition hover:bg-white/20 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/60"
            aria-label={attachment_label(@attachment, "Open audio")}
          >
            <.icon name="hero-arrows-pointing-out" class="size-4" />
          </button>
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
