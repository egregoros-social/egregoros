defmodule EgregorosWeb.StatusCard do
  use EgregorosWeb, :html

  alias Egregoros.CustomEmojis
  alias Egregoros.HTML
  alias Egregoros.User
  alias EgregorosWeb.ProfilePaths
  alias EgregorosWeb.URL

  @content_collapse_threshold 500
  @default_reactions ["🔥", "👍", "❤️"]

  attr :id, :string, required: true
  attr :entry, :map, required: true
  attr :current_user, :any, default: nil
  attr :reply_mode, :atom, default: :navigate

  def status_card(assigns) do
    ~H"""
    <article
      id={@id}
      data-role="status-card"
      class="rounded-xl border border-slate-200 bg-white p-5 shadow-sm transition hover:shadow-md dark:border-slate-700 dark:bg-slate-800/50 motion-safe:animate-rise"
    >
      <div class="flex items-start justify-between gap-3">
        <div class="flex min-w-0 items-start gap-3">
          <%= if is_binary(profile_path = actor_profile_path(@entry.actor)) do %>
            <.link
              navigate={profile_path}
              data-role="actor-link"
              class="group flex min-w-0 items-start gap-3 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-500 rounded-lg"
            >
              <div class="shrink-0">
                <.actor_avatar actor={@entry.actor} />
              </div>

              <div class="min-w-0">
                <p
                  data-role="post-actor-name"
                  class="truncate font-semibold text-slate-900 group-hover:text-violet-600 dark:text-white dark:group-hover:text-violet-400"
                >
                  {@entry.actor.display_name}
                </p>
                <div class="mt-0.5 flex flex-wrap items-center gap-2">
                  <span
                    data-role="post-actor-handle"
                    class="truncate text-sm text-slate-500 dark:text-slate-400"
                  >
                    {@entry.actor.handle}
                  </span>

                  <span class={[
                    "inline-flex items-center rounded px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide",
                    @entry.object.local &&
                      "bg-teal-100 text-teal-700 dark:bg-teal-900/50 dark:text-teal-300",
                    !@entry.object.local &&
                      "bg-slate-100 text-slate-600 dark:bg-slate-700 dark:text-slate-400"
                  ]}>
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
                class="truncate font-semibold text-slate-900 dark:text-white"
              >
                {@entry.actor.display_name}
              </p>
              <div class="mt-0.5 flex flex-wrap items-center gap-2">
                <span
                  data-role="post-actor-handle"
                  class="truncate text-sm text-slate-500 dark:text-slate-400"
                >
                  {@entry.actor.handle}
                </span>

                <span class={[
                  "inline-flex items-center rounded px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide",
                  @entry.object.local &&
                    "bg-teal-100 text-teal-700 dark:bg-teal-900/50 dark:text-teal-300",
                  !@entry.object.local &&
                    "bg-slate-100 text-slate-600 dark:bg-slate-700 dark:text-slate-400"
                ]}>
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
              class="inline-flex focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-500 rounded"
              aria-label="Open post"
            >
              <.time_ago at={@entry.object.inserted_at} />
            </.link>
          <% else %>
            <.time_ago at={@entry.object.inserted_at} />
          <% end %>

          <.status_menu entry={@entry} current_user={@current_user} />
        </div>
      </div>

      <% content_warning = content_warning_text(@entry.object) %>

      <%= if is_binary(content_warning) do %>
        <details data-role="content-warning" class="group mt-4">
          <summary class="flex cursor-pointer items-center justify-between gap-4 rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-left transition hover:bg-amber-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-500 dark:border-amber-700/50 dark:bg-amber-900/20 dark:hover:bg-amber-900/30 list-none [&::-webkit-details-marker]:hidden">
            <div class="flex min-w-0 items-start gap-3">
              <span class="mt-0.5 inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-amber-200 text-amber-700 dark:bg-amber-800/50 dark:text-amber-300">
                <.icon name="hero-exclamation-triangle" class="size-4" />
              </span>

              <div class="min-w-0">
                <p class="text-xs font-semibold uppercase tracking-wide text-amber-700 dark:text-amber-300">
                  Content warning
                </p>
                <p
                  data-role="content-warning-text"
                  class="mt-1 truncate font-medium text-slate-900 dark:text-slate-100"
                  title={content_warning}
                >
                  {content_warning}
                </p>
              </div>
            </div>

            <span class="inline-flex shrink-0 items-center gap-2 rounded-lg bg-white px-3 py-1.5 text-xs font-semibold text-slate-700 shadow-sm dark:bg-slate-800 dark:text-slate-200">
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

      <div
        :if={@current_user}
        class="mt-4 flex flex-wrap items-center justify-between gap-3 border-t border-slate-100 pt-4 dark:border-slate-700"
      >
        <div class="flex flex-wrap items-center gap-2">
          <%= if @reply_mode == :modal do %>
            <button
              type="button"
              data-role="reply"
              phx-click={
                JS.dispatch("egregoros:reply-open", to: "#reply-modal")
                |> JS.push("open_reply_modal")
              }
              phx-value-in_reply_to={@entry.object.ap_id}
              phx-value-actor_handle={@entry.actor.handle}
              class="inline-flex cursor-pointer items-center gap-2 rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-medium text-slate-600 shadow-sm transition hover:bg-slate-50 hover:text-slate-900 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-500 dark:border-slate-600 dark:bg-slate-700 dark:text-slate-300 dark:hover:bg-slate-600 dark:hover:text-white"
              aria-label="Reply"
            >
              <.icon name="hero-chat-bubble-left-right" class="size-5" />
              <span class="sr-only">Reply</span>
            </button>
          <% else %>
            <%= if is_binary(reply_path = status_reply_path(@entry)) do %>
              <.link
                navigate={reply_path}
                data-role="reply"
                class="inline-flex cursor-pointer items-center gap-2 rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-medium text-slate-600 shadow-sm transition hover:bg-slate-50 hover:text-slate-900 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-500 dark:border-slate-600 dark:bg-slate-700 dark:text-slate-300 dark:hover:bg-slate-600 dark:hover:text-white"
                aria-label="Reply"
              >
                <.icon name="hero-chat-bubble-left-right" class="size-5" />
                <span class="sr-only">Reply</span>
              </.link>
            <% end %>
          <% end %>

          <button
            type="button"
            data-role="like"
            phx-click="toggle_like"
            phx-value-id={@entry.object.id}
            phx-disable-with="..."
            aria-pressed={@entry.liked?}
            class={[
              "inline-flex cursor-pointer items-center gap-2 rounded-lg border px-3 py-2 text-sm font-medium shadow-sm transition",
              @entry.liked? &&
                "border-rose-200 bg-rose-50 text-rose-700 hover:bg-rose-100 dark:border-rose-700/50 dark:bg-rose-900/30 dark:text-rose-300 dark:hover:bg-rose-900/50",
              !@entry.liked? &&
                "border-slate-200 bg-white text-slate-600 hover:bg-slate-50 hover:text-slate-900 dark:border-slate-600 dark:bg-slate-700 dark:text-slate-300 dark:hover:bg-slate-600 dark:hover:text-white"
            ]}
          >
            <.icon
              name={if @entry.liked?, do: "hero-heart-solid", else: "hero-heart"}
              class="size-5"
            />
            <span class="sr-only">{if @entry.liked?, do: "Unlike", else: "Like"}</span>
            <span class="text-xs font-semibold tabular-nums">
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
              "inline-flex cursor-pointer items-center gap-2 rounded-lg border px-3 py-2 text-sm font-medium shadow-sm transition",
              @entry.reposted? &&
                "border-emerald-200 bg-emerald-50 text-emerald-700 hover:bg-emerald-100 dark:border-emerald-700/50 dark:bg-emerald-900/30 dark:text-emerald-300 dark:hover:bg-emerald-900/50",
              !@entry.reposted? &&
                "border-slate-200 bg-white text-slate-600 hover:bg-slate-50 hover:text-slate-900 dark:border-slate-600 dark:bg-slate-700 dark:text-slate-300 dark:hover:bg-slate-600 dark:hover:text-white"
            ]}
          >
            <.icon
              name={if @entry.reposted?, do: "hero-arrow-path-solid", else: "hero-arrow-path"}
              class="size-5"
            />
            <span class="sr-only">{if @entry.reposted?, do: "Unrepost", else: "Repost"}</span>
            <span class="text-xs font-semibold tabular-nums">
              {@entry.reposts_count}
            </span>
          </button>
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <%= for emoji <- reaction_order(@entry.reactions) do %>
            <% reaction = Map.get(@entry.reactions || %{}, emoji, %{count: 0, reacted?: false}) %>

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
                "inline-flex cursor-pointer items-center gap-2 rounded-lg border px-3 py-2 text-sm font-medium shadow-sm transition",
                reaction.reacted? &&
                  "border-emerald-200 bg-emerald-50 text-emerald-700 hover:bg-emerald-100 dark:border-emerald-700/50 dark:bg-emerald-900/30 dark:text-emerald-300 dark:hover:bg-emerald-900/50",
                !reaction.reacted? &&
                  "border-slate-200 bg-white text-slate-600 hover:bg-slate-50 hover:text-slate-900 dark:border-slate-600 dark:bg-slate-700 dark:text-slate-300 dark:hover:bg-slate-600 dark:hover:text-white"
              ]}
            >
              <span class="text-base leading-none">{emoji}</span>
              <span class="text-xs font-semibold tabular-nums">{reaction.count || 0}</span>
            </button>
          <% end %>

          <details
            id={"reaction-picker-#{@entry.object.id}"}
            data-role="reaction-picker"
            class="relative"
          >
            <summary class="list-none cursor-pointer [&::-webkit-details-marker]:hidden">
              <span class="inline-flex h-9 w-9 items-center justify-center rounded-lg border border-slate-200 bg-white text-slate-500 shadow-sm transition hover:bg-slate-50 hover:text-slate-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-500 dark:border-slate-600 dark:bg-slate-700 dark:text-slate-400 dark:hover:bg-slate-600 dark:hover:text-slate-200">
                <.icon name="hero-face-smile" class="size-5" />
                <span class="sr-only">Add reaction</span>
              </span>
            </summary>

            <div
              class="absolute right-0 top-11 z-40 w-64 overflow-hidden rounded-xl border border-slate-200 bg-white p-4 shadow-xl dark:border-slate-700 dark:bg-slate-800"
              phx-click-away={JS.remove_attribute("open", to: "#reaction-picker-#{@entry.object.id}")}
            >
              <p class="text-xs font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-400">
                React
              </p>

              <div class="mt-3 grid grid-cols-8 gap-1">
                <button
                  :for={emoji <- reaction_picker_emojis()}
                  type="button"
                  data-role="reaction-picker-option"
                  data-emoji={emoji}
                  phx-click={
                    JS.push("toggle_reaction", value: %{id: @entry.object.id, emoji: emoji})
                    |> JS.remove_attribute("open", to: "#reaction-picker-#{@entry.object.id}")
                  }
                  class="inline-flex cursor-pointer h-9 w-9 items-center justify-center rounded-lg text-xl transition hover:bg-slate-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-500 dark:hover:bg-slate-700"
                >
                  {emoji}
                </button>
              </div>
            </div>
          </details>
        </div>
      </div>
    </article>
    """
  end

  defp reaction_picker_emojis do
    ["😀", "😂", "😍", "😮", "😢", "😡", "🔥", "👍", "❤️", "🎉", "🙏", "🤔", "🥳", "😎", "💯", "✨"]
  end

  defp reaction_order(%{} = reactions) do
    custom =
      reactions
      |> Map.keys()
      |> Enum.reject(&(&1 in @default_reactions))
      |> Enum.sort()

    (@default_reactions ++ custom)
    |> Enum.uniq()
  end

  defp reaction_order(_reactions), do: @default_reactions

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
        "mt-4 text-base leading-relaxed text-slate-700 dark:text-slate-200",
        collapsible_content && "relative max-h-64 overflow-hidden"
      ]}
    >
      {post_content_html(@entry.object)}

      <div
        :if={collapsible_content}
        id={fade_id}
        class="pointer-events-none absolute inset-x-0 bottom-0 h-20 bg-gradient-to-t from-white to-transparent dark:from-slate-800/50"
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
      class="mt-3 inline-flex items-center gap-2 rounded-lg bg-slate-100 px-3 py-1.5 text-xs font-semibold text-slate-700 transition hover:bg-slate-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-500 dark:bg-slate-700 dark:text-slate-300 dark:hover:bg-slate-600"
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
      class="mt-4 flex items-center justify-between gap-4 rounded-lg border border-rose-200 bg-rose-50 px-4 py-3 dark:border-rose-700/50 dark:bg-rose-900/20"
    >
      <div class="flex min-w-0 items-center gap-3">
        <span class="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-rose-200 text-rose-700 dark:bg-rose-800/50 dark:text-rose-300">
          <.icon name="hero-eye-slash" class="size-4" />
        </span>

        <div class="min-w-0">
          <p class="font-semibold text-slate-900 dark:text-slate-100">Sensitive media</p>
          <p class="mt-0.5 text-sm text-slate-600 dark:text-slate-400">Hidden by default.</p>
        </div>
      </div>

      <button
        type="button"
        data-role="sensitive-media-reveal"
        phx-click={
          JS.hide(to: "#sensitive-media-#{@entry.object.id}")
          |> JS.remove_class("hidden", to: "#attachments-#{@entry.object.id}")
        }
        class="inline-flex items-center gap-2 rounded-lg bg-slate-900 px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-slate-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-500 dark:bg-white dark:text-slate-900 dark:hover:bg-slate-100"
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
        class="group overflow-hidden rounded-lg border border-slate-200 bg-slate-50 dark:border-slate-700 dark:bg-slate-800"
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
    emojis = CustomEmojis.from_object(object)

    format =
      case Map.get(object, :local) do
        false -> :html
        _ -> :text
      end

    raw
    |> HTML.to_safe_html(format: format, emojis: emojis)
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

  defp status_permalink_path(%{object: %{id: id, local: false}, actor: actor})
       when is_integer(id) do
    case ProfilePaths.profile_path(actor) do
      "/@" <> _rest = profile_path -> profile_path <> "/" <> Integer.to_string(id)
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
    path = status_permalink_path(entry)

    cond do
      Map.get(object, :local) == true and is_binary(path) and path != "" ->
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
  attr :current_user, :any, default: nil

  defp status_menu(assigns) do
    assigns =
      assigns
      |> assign(:share_url, status_share_url(assigns.entry))
      |> assign(:can_delete?, can_delete_post?(assigns.entry, assigns.current_user))
      |> assign(:bookmarked?, Map.get(assigns.entry, :bookmarked?, false))

    ~H"""
    <details data-role="status-menu" class="relative">
      <summary class="list-none [&::-webkit-details-marker]:hidden">
        <span class="inline-flex h-8 w-8 items-center justify-center rounded-lg text-slate-400 transition hover:bg-slate-100 hover:text-slate-600 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-500 dark:text-slate-500 dark:hover:bg-slate-700 dark:hover:text-slate-300">
          <.icon name="hero-ellipsis-horizontal" class="size-5" />
        </span>
      </summary>

      <div class="absolute right-0 top-9 z-40 w-48 overflow-hidden rounded-xl border border-slate-200 bg-white shadow-xl dark:border-slate-700 dark:bg-slate-800">
        <button
          :if={is_binary(@share_url) and @share_url != ""}
          type="button"
          data-role="copy-link"
          data-copy-text={@share_url}
          phx-click={JS.dispatch("egregoros:copy") |> JS.push("copied_link")}
          class="flex w-full items-center gap-3 px-4 py-2.5 text-sm font-medium text-slate-700 transition hover:bg-slate-50 dark:text-slate-200 dark:hover:bg-slate-700"
        >
          <.icon name="hero-clipboard-document" class="size-5 text-slate-500 dark:text-slate-400" />
          Copy link
        </button>

        <a
          :if={is_binary(@share_url) and @share_url != ""}
          data-role="open-link"
          href={@share_url}
          target="_blank"
          rel="nofollow noopener noreferrer"
          class="flex items-center gap-3 px-4 py-2.5 text-sm font-medium text-slate-700 transition hover:bg-slate-50 dark:text-slate-200 dark:hover:bg-slate-700"
        >
          <.icon
            name="hero-arrow-top-right-on-square"
            class="size-5 text-slate-500 dark:text-slate-400"
          /> Open link
        </a>

        <button
          :if={@current_user}
          type="button"
          data-role="bookmark"
          phx-click="toggle_bookmark"
          phx-value-id={@entry.object.id}
          phx-disable-with="..."
          class={[
            "flex w-full items-center gap-3 px-4 py-2.5 text-sm font-medium transition hover:bg-slate-50 dark:hover:bg-slate-700",
            @bookmarked? && "text-violet-700 dark:text-violet-400",
            !@bookmarked? && "text-slate-700 dark:text-slate-200"
          ]}
        >
          <.icon
            name={if @bookmarked?, do: "hero-bookmark-solid", else: "hero-bookmark"}
            class={[
              "size-5",
              @bookmarked? && "text-violet-600 dark:text-violet-400",
              !@bookmarked? && "text-slate-500 dark:text-slate-400"
            ]}
          />
          {if @bookmarked?, do: "Unbookmark", else: "Bookmark"}
        </button>

        <%= if @can_delete? do %>
          <div class="border-t border-slate-200 dark:border-slate-700">
            <button
              type="button"
              data-role="delete-post"
              phx-click={JS.toggle(to: "#delete-post-confirm-#{@entry.object.id}")}
              class="flex w-full items-center gap-3 px-4 py-2.5 text-sm font-medium text-red-600 transition hover:bg-red-50 dark:text-red-400 dark:hover:bg-red-900/20"
            >
              <.icon name="hero-trash" class="size-5" /> Delete post
            </button>

            <div
              id={"delete-post-confirm-#{@entry.object.id}"}
              class="hidden space-y-3 px-4 pb-4 pt-2 text-sm"
            >
              <p class="text-slate-500 dark:text-slate-400">
                This cannot be undone.
              </p>

              <div class="flex items-center justify-end gap-2">
                <button
                  type="button"
                  data-role="delete-post-cancel"
                  phx-click={JS.hide(to: "#delete-post-confirm-#{@entry.object.id}")}
                  class="inline-flex items-center justify-center rounded-lg border border-slate-200 bg-white px-3 py-1.5 text-xs font-semibold text-slate-700 transition hover:bg-slate-50 dark:border-slate-600 dark:bg-slate-700 dark:text-slate-200 dark:hover:bg-slate-600"
                >
                  Cancel
                </button>

                <button
                  type="button"
                  data-role="delete-post-confirm"
                  phx-click="delete_post"
                  phx-value-id={@entry.object.id}
                  phx-disable-with="Deleting..."
                  class="inline-flex items-center justify-center rounded-lg bg-red-600 px-3 py-1.5 text-xs font-semibold text-white shadow-sm transition hover:bg-red-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-red-500"
                >
                  Delete
                </button>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </details>
    """
  end

  defp can_delete_post?(%{object: %{type: "Note", local: true, actor: actor}}, %User{ap_id: actor})
       when is_binary(actor) and actor != "" do
    true
  end

  defp can_delete_post?(_entry, _user), do: false

  attr :actor, :map, required: true

  defp actor_avatar(assigns) do
    ~H"""
    <%= if is_binary(@actor.avatar_url) and @actor.avatar_url != "" do %>
      <img
        src={@actor.avatar_url}
        alt={@actor.display_name}
        class="h-11 w-11 rounded-xl border-2 border-slate-200 bg-white object-cover dark:border-slate-600 dark:bg-slate-700"
        loading="lazy"
      />
    <% else %>
      <div class="flex h-11 w-11 items-center justify-center rounded-xl border-2 border-slate-200 bg-slate-100 font-bold text-slate-600 dark:border-slate-600 dark:bg-slate-700 dark:text-slate-300">
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
    <%= case EgregorosWeb.Attachments.kind(@attachment) do %>
      <% :image -> %>
        <button
          type="button"
          data-role="attachment-open"
          data-index={@index}
          phx-click={JS.dispatch("egregoros:media-open", to: "#media-viewer")}
          class="block w-full text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-500"
          aria-label={attachment_label(@attachment, "Open image")}
        >
          <img
            data-role="attachment"
            data-kind="image"
            src={@attachment.href}
            alt={@attachment.description}
            class="h-44 w-full object-cover transition duration-300 group-hover:scale-105"
            loading="lazy"
          />
        </button>
      <% :video -> %>
        <div class="group relative">
          <video
            data-role="attachment"
            data-kind="video"
            class="h-44 w-full bg-black object-cover"
            controls
            preload="metadata"
            playsinline
            aria-label={attachment_label(@attachment, "Video attachment")}
          >
            <source
              src={@attachment.href}
              type={EgregorosWeb.Attachments.source_type(@attachment, "video/mp4")}
            />
          </video>

          <button
            type="button"
            data-role="attachment-open"
            data-index={@index}
            phx-click={JS.dispatch("egregoros:media-open", to: "#media-viewer")}
            class="absolute right-3 top-3 inline-flex h-8 w-8 items-center justify-center rounded-lg bg-black/50 text-white transition hover:bg-black/70 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/60"
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
              type={EgregorosWeb.Attachments.source_type(@attachment, "audio/mpeg")}
            />
          </audio>

          <button
            type="button"
            data-role="attachment-open"
            data-index={@index}
            phx-click={JS.dispatch("egregoros:media-open", to: "#media-viewer")}
            class="absolute right-3 top-3 inline-flex h-8 w-8 items-center justify-center rounded-lg bg-slate-200 text-slate-600 transition hover:bg-slate-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-500 dark:bg-slate-700 dark:text-slate-300 dark:hover:bg-slate-600"
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
          rel="nofollow noopener noreferrer"
          class="flex h-44 w-full items-center justify-center gap-3 px-4 font-medium text-slate-700 transition hover:bg-slate-100 dark:text-slate-200 dark:hover:bg-slate-700"
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
