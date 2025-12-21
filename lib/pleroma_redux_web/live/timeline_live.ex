defmodule PleromaReduxWeb.TimelineLive do
  use PleromaReduxWeb, :live_view

  alias PleromaRedux.Interactions
  alias PleromaRedux.Media
  alias PleromaRedux.MediaStorage
  alias PleromaRedux.Notifications
  alias PleromaRedux.Objects
  alias PleromaRedux.Publish
  alias PleromaRedux.Relationships
  alias PleromaRedux.Timeline
  alias PleromaRedux.User
  alias PleromaRedux.Users
  alias PleromaReduxWeb.ViewModels.Status, as: StatusVM

  @page_size 20
  @compose_max_chars 5000

  @impl true
  def mount(params, session, socket) do
    if connected?(socket) do
      Timeline.subscribe()
    end

    current_user =
      case Map.get(session, "user_id") do
        nil -> nil
        id -> Users.get(id)
      end

    timeline = timeline_from_params(params, current_user)

    form = Phoenix.Component.to_form(default_post_params(), as: :post)

    posts = list_timeline_posts(timeline, current_user, limit: @page_size)

    socket =
      socket
      |> assign(
        timeline: timeline,
        home_actor_ids: home_actor_ids(current_user),
        notifications_count: notifications_count(current_user),
        compose_open?: false,
        compose_options_open?: false,
        compose_cw_open?: false,
        error: nil,
        pending_posts: [],
        timeline_at_top?: true,
        media_viewer: nil,
        form: form,
        media_alt: %{},
        posts_cursor: posts_cursor(posts),
        posts_end?: length(posts) < @page_size,
        current_user: current_user
      )
      |> stream(:posts, StatusVM.decorate_many(posts, current_user), dom_id: &post_dom_id/1)
      |> allow_upload(:media,
        accept: ~w(
          .png
          .jpg
          .jpeg
          .webp
          .gif
          .heic
          .heif
          .mp4
          .webm
          .mov
          .m4a
          .mp3
          .ogg
          .opus
          .wav
          .aac
        ),
        max_entries: 4,
        max_file_size: 10_000_000,
        auto_upload: true
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    timeline = timeline_from_params(params, socket.assigns.current_user)

    socket =
      if timeline == socket.assigns.timeline do
        socket
      else
        posts = list_timeline_posts(timeline, socket.assigns.current_user, limit: @page_size)

        socket
        |> assign(
          timeline: timeline,
          pending_posts: [],
          timeline_at_top?: true,
          posts_cursor: posts_cursor(posts),
          posts_end?: length(posts) < @page_size
        )
        |> stream(:posts, StatusVM.decorate_many(posts, socket.assigns.current_user),
          reset: true,
          dom_id: &post_dom_id/1
        )
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("compose_change", %{"post" => %{} = post_params}, socket) do
    post_params = Map.merge(default_post_params(), post_params)
    media_alt = Map.get(post_params, "media_alt", %{})

    compose_options_open? = truthy?(Map.get(post_params, "ui_options_open"))

    compose_cw_open? =
      socket.assigns.compose_cw_open? ||
        post_params |> Map.get("spoiler_text", "") |> to_string() |> String.trim() != ""

    {:noreply,
     assign(socket,
       form: Phoenix.Component.to_form(post_params, as: :post),
       media_alt: media_alt,
       compose_options_open?: compose_options_open?,
       compose_cw_open?: compose_cw_open?
     )}
  end

  def handle_event("open_compose", _params, socket) do
    {:noreply, assign(socket, compose_open?: true)}
  end

  def handle_event("close_compose", _params, socket) do
    {:noreply, assign(socket, compose_open?: false)}
  end

  def handle_event("toggle_compose_cw", _params, socket) do
    if socket.assigns.compose_cw_open? do
      post_params =
        default_post_params()
        |> Map.merge(socket.assigns.form.params)
        |> Map.put("spoiler_text", "")

      {:noreply,
       assign(socket,
         compose_cw_open?: false,
         form: Phoenix.Component.to_form(post_params, as: :post)
       )}
    else
      {:noreply, assign(socket, compose_cw_open?: true)}
    end
  end

  def handle_event("timeline_at_top", %{"at_top" => at_top}, socket) do
    at_top? = truthy?(at_top)

    socket =
      socket
      |> assign(:timeline_at_top?, at_top?)
      |> maybe_flush_pending_posts(at_top?)

    {:noreply, socket}
  end

  def handle_event("copied_link", _params, socket) do
    {:noreply, put_flash(socket, :info, "Copied link to clipboard.")}
  end

  def handle_event("open_media", %{} = params, socket) do
    socket = MediaViewer.open(socket, params, socket.assigns.current_user)
    {:noreply, socket}
  end

  def handle_event("close_media", _params, socket) do
    {:noreply, MediaViewer.close(socket)}
  end

  def handle_event("media_next", _params, socket) do
    {:noreply, MediaViewer.next(socket)}
  end

  def handle_event("media_prev", _params, socket) do
    {:noreply, MediaViewer.prev(socket)}
  end

  def handle_event("media_keydown", %{} = params, socket) do
    {:noreply, MediaViewer.handle_keydown(socket, params)}
  end

  def handle_event("cancel_media", %{"ref" => ref}, socket) do
    {:noreply,
     socket
     |> cancel_upload(:media, ref)
     |> assign(:media_alt, Map.delete(socket.assigns.media_alt, ref))}
  end

  def handle_event("create_post", %{"post" => %{} = post_params}, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, assign(socket, error: "Register to post.")}

      user ->
        post_params = Map.merge(default_post_params(), post_params)
        content = post_params |> Map.get("content", "") |> to_string()
        media_alt = Map.get(post_params, "media_alt", %{})
        visibility = Map.get(post_params, "visibility", "public")
        spoiler_text = Map.get(post_params, "spoiler_text")
        sensitive = Map.get(post_params, "sensitive")
        language = Map.get(post_params, "language")

        upload = socket.assigns.uploads.media

        cond do
          Enum.any?(upload.entries, &(!&1.done?)) ->
            {:noreply,
             assign(socket,
               error: "Wait for attachments to finish uploading.",
               form: Phoenix.Component.to_form(post_params, as: :post),
               media_alt: media_alt
             )}

          upload.errors != [] or Enum.any?(upload.entries, &(!&1.valid?)) ->
            {:noreply,
             assign(socket,
               error: "Remove invalid attachments before posting.",
               form: Phoenix.Component.to_form(post_params, as: :post),
               media_alt: media_alt
             )}

          true ->
            attachments =
              consume_uploaded_entries(socket, :media, fn %{path: path}, entry ->
                upload = %Plug.Upload{
                  path: path,
                  filename: entry.client_name,
                  content_type: entry.client_type
                }

                description = media_alt |> Map.get(entry.ref, "") |> to_string() |> String.trim()

                with {:ok, url_path} <- MediaStorage.store_media(user, upload),
                     {:ok, object} <-
                       Media.create_media_object(user, upload, url_path, description: description) do
                  {:ok, object.data}
                else
                  {:error, reason} -> {:ok, {:error, reason}}
                end
              end)

            case Enum.find(attachments, &match?({:error, _}, &1)) do
              {:error, _reason} ->
                {:noreply,
                 assign(socket,
                   error: "Could not upload attachment.",
                   form: Phoenix.Component.to_form(post_params, as: :post),
                   media_alt: media_alt
                 )}

              nil ->
                case Publish.post_note(user, content,
                       attachments: attachments,
                       visibility: visibility,
                       spoiler_text: spoiler_text,
                       sensitive: sensitive,
                       language: language
                     ) do
                  {:ok, _post} ->
                    {:noreply,
                     assign(socket,
                       form: Phoenix.Component.to_form(default_post_params(), as: :post),
                       compose_open?: false,
                       compose_options_open?: false,
                       compose_cw_open?: false,
                       error: nil,
                       media_alt: %{}
                     )}

                  {:error, :too_long} ->
                    {:noreply,
                     assign(socket,
                       error: "Post is too long.",
                       form: Phoenix.Component.to_form(post_params, as: :post),
                       media_alt: media_alt
                     )}

                  {:error, :empty} ->
                    {:noreply,
                     assign(socket,
                       error: "Post can't be empty.",
                       form: Phoenix.Component.to_form(post_params, as: :post),
                       media_alt: media_alt
                     )}
                end
            end
        end
    end
  end

  def handle_event("toggle_like", %{"id" => id}, socket) do
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)) do
      _ = Interactions.toggle_like(user, post_id)

      {:noreply, refresh_post(socket, post_id)}
    else
      nil ->
        {:noreply, assign(socket, error: "Register to like posts.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_repost", %{"id" => id}, socket) do
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)) do
      _ = Interactions.toggle_repost(user, post_id)

      {:noreply, refresh_post(socket, post_id)}
    else
      nil ->
        {:noreply, assign(socket, error: "Register to repost.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_reaction", %{"id" => id, "emoji" => emoji}, socket) do
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)) do
      emoji = to_string(emoji)
      _ = Interactions.toggle_reaction(user, post_id, emoji)

      {:noreply, refresh_post(socket, post_id)}
    else
      nil ->
        {:noreply, assign(socket, error: "Register to react.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_post", %{"id" => id}, socket) do
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)),
         {:ok, _delete} <- Interactions.delete_post(user, post_id) do
      {:noreply,
       socket
       |> put_flash(:info, "Post deleted.")
       |> stream_delete(:posts, %{object: %{id: post_id}})}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to delete posts.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not delete post.")}
    end
  end

  def handle_event("load_more", _params, socket) do
    cursor = socket.assigns.posts_cursor

    cond do
      socket.assigns.posts_end? ->
        {:noreply, socket}

      is_nil(cursor) ->
        {:noreply, assign(socket, posts_end?: true)}

      true ->
        posts =
          list_timeline_posts(socket.assigns.timeline, socket.assigns.current_user,
            limit: @page_size,
            max_id: cursor
          )

        socket =
          if posts == [] do
            assign(socket, posts_end?: true)
          else
            new_cursor = posts_cursor(posts)
            posts_end? = length(posts) < @page_size
            current_user = socket.assigns.current_user

            Enum.reduce(StatusVM.decorate_many(posts, current_user), socket, fn entry, socket ->
              stream_insert(socket, :posts, entry, at: -1)
            end)
            |> assign(posts_cursor: new_cursor, posts_end?: posts_end?)
          end

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:post_created, post}, socket) do
    if include_post?(post, socket.assigns.timeline, socket.assigns.home_actor_ids) do
      if socket.assigns.timeline_at_top? do
        cursor =
          case socket.assigns.posts_cursor do
            nil -> post.id
            existing -> min(existing, post.id)
          end

        {:noreply,
         socket
         |> stream_insert(:posts, StatusVM.decorate(post, socket.assigns.current_user), at: 0)
         |> assign(:posts_cursor, cursor)}
      else
        pending_posts =
          [post | socket.assigns.pending_posts]
          |> Enum.uniq_by(& &1.id)
          |> Enum.take(50)

        {:noreply, assign(socket, pending_posts: pending_posts)}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <AppShell.app_shell
        id="timeline-shell"
        nav_id="timeline-sidebar"
        main_id="timeline-feed"
        active={:timeline}
        current_user={@current_user}
        notifications_count={@notifications_count}
      >
        <:nav_top>
          <section
            id="compose-panel"
            data-role="compose-panel"
            data-state={if @compose_open?, do: "open", else: "closed"}
            class={[
              "rounded-3xl border border-white/80 bg-white/80 p-6 shadow-xl shadow-slate-200/40 backdrop-blur dark:border-slate-700/60 dark:bg-slate-900/70 dark:shadow-slate-900/40",
              "fixed inset-x-4 bottom-24 z-50 max-h-[78vh] overflow-y-auto lg:static lg:inset-auto lg:bottom-auto lg:z-auto lg:max-h-none lg:overflow-visible",
              !@compose_open? && "hidden lg:block"
            ]}
          >
            <div
              id="compose-mobile-header"
              data-role="compose-mobile-header"
              data-state={if @compose_open?, do: "open", else: "closed"}
              class={[
                "mb-4 flex items-center justify-between lg:hidden",
                !@compose_open? && "hidden"
              ]}
            >
              <p class="text-xs font-semibold uppercase tracking-[0.3em] text-slate-500 dark:text-slate-400">
                Compose
              </p>
              <button
                type="button"
                data-role="compose-close"
                phx-click={close_compose_js() |> JS.push("close_compose")}
                class="inline-flex h-9 w-9 items-center justify-center rounded-2xl text-slate-500 transition hover:bg-slate-900/5 hover:text-slate-900 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:text-slate-300 dark:hover:bg-white/10 dark:hover:text-white"
                aria-label="Close composer"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>

            <div class="flex items-center justify-between">
              <div>
                <p class="text-xs uppercase tracking-[0.3em] text-slate-500 dark:text-slate-400">
                  Compose
                </p>
                <h2 class="mt-2 font-display text-xl text-slate-900 dark:text-slate-100">
                  New post
                </h2>
              </div>
              <div class="hidden text-right text-xs text-slate-500 dark:text-slate-400 sm:block">
                Live updates
              </div>
            </div>

            <%= if @current_user do %>
              <.form
                for={@form}
                id="timeline-form"
                phx-change="compose_change"
                phx-submit="create_post"
                class="mt-6 space-y-3"
              >
                <.input
                  type="hidden"
                  id="compose-options-state"
                  name="post[ui_options_open]"
                  value={Map.get(@form.params || %{}, "ui_options_open", "false")}
                  data-role="compose-options-state"
                />

                <div
                  data-role="compose-editor"
                  phx-drop-target={@uploads.media.ref}
                  class="overflow-hidden rounded-2xl border border-slate-200/80 bg-white/70 shadow-sm shadow-slate-200/20 transition focus-within:border-slate-400 focus-within:ring-2 focus-within:ring-slate-200 dark:border-slate-700/80 dark:bg-slate-950/60 dark:shadow-slate-900/30 dark:focus-within:border-slate-400 dark:focus-within:ring-slate-600"
                >
                  <div class="flex flex-wrap gap-2 px-4 pt-4">
                    <button
                      type="button"
                      data-role="compose-visibility-pill"
                      phx-click={toggle_compose_options_js()}
                      class="inline-flex items-center gap-2 rounded-xl border border-slate-200/80 bg-white/70 px-3 py-2 text-xs font-semibold text-slate-700 transition hover:bg-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:hover:bg-slate-950"
                      aria-label="Post visibility"
                    >
                      <.icon name="hero-globe-alt" class="size-4 opacity-80" />
                      {visibility_label(Map.get(@form.params || %{}, "visibility"))}
                    </button>

                    <button
                      type="button"
                      data-role="compose-language-pill"
                      phx-click={toggle_compose_options_js()}
                      class="inline-flex items-center gap-2 rounded-xl border border-slate-200/80 bg-white/70 px-3 py-2 text-xs font-semibold text-slate-700 transition hover:bg-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:hover:bg-slate-950"
                      aria-label="Post language"
                    >
                      <.icon name="hero-language" class="size-4 opacity-80" />
                      {language_label(Map.get(@form.params || %{}, "language"))}
                    </button>
                  </div>

                  <div
                    id="compose-cw"
                    data-role="compose-cw"
                    data-state={if @compose_cw_open?, do: "open", else: "closed"}
                    class={["px-4 pt-3", !@compose_cw_open? && "hidden"]}
                  >
                    <.input
                      type="text"
                      field={@form[:spoiler_text]}
                      placeholder="Content warning"
                      phx-debounce="blur"
                      class="w-full rounded-xl border border-slate-200/80 bg-white/70 px-3 py-2 text-sm text-slate-900 outline-none transition focus:border-slate-400 focus:ring-2 focus:ring-slate-200 dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-100 dark:focus:border-slate-400 dark:focus:ring-slate-600"
                    />
                  </div>

                  <div class="px-4 pb-4 pt-3">
                    <.input
                      type="textarea"
                      field={@form[:content]}
                      data-role="compose-content"
                      data-max-chars={compose_max_chars()}
                      phx-hook="ComposeCharCounter"
                      placeholder="What's on your mind?"
                      rows="6"
                      phx-debounce="blur"
                      class="min-h-[7rem] w-full resize-none border-0 bg-transparent p-0 text-base leading-6 text-slate-900 outline-none placeholder:text-slate-400 focus:ring-0 dark:text-slate-100 dark:placeholder:text-slate-500"
                    />
                  </div>

                  <div
                    id="compose-options"
                    data-role="compose-options"
                    data-state={if @compose_options_open?, do: "open", else: "closed"}
                    class={[
                      "border-t border-slate-200/70 bg-white/60 px-4 py-4 dark:border-slate-700/70 dark:bg-slate-950/40",
                      !@compose_options_open? && "hidden"
                    ]}
                  >
                    <div class="grid gap-4">
                      <.input
                        type="select"
                        field={@form[:visibility]}
                        label="Visibility"
                        options={[
                          Public: "public",
                          Unlisted: "unlisted",
                          Private: "private",
                          Direct: "direct"
                        ]}
                      />

                      <.input
                        type="text"
                        field={@form[:language]}
                        label="Language"
                        placeholder="Optional (e.g. en)"
                        phx-debounce="blur"
                      />

                      <.input
                        type="checkbox"
                        field={@form[:sensitive]}
                        label="Mark media as sensitive"
                      />
                    </div>
                  </div>

                  <div
                    :if={@uploads.media.entries != [] or upload_errors(@uploads.media) != []}
                    data-role="compose-media"
                    class="border-t border-slate-200/70 bg-white/60 px-4 py-4 dark:border-slate-700/70 dark:bg-slate-950/40"
                  >
                    <div class="grid gap-3">
                      <div
                        :for={entry <- @uploads.media.entries}
                        id={"media-entry-#{entry.ref}"}
                        data-role="media-entry"
                        class="rounded-2xl border border-slate-200/80 bg-white/60 p-3 shadow-sm shadow-slate-200/20 dark:border-slate-700/70 dark:bg-slate-950/50 dark:shadow-slate-900/40"
                      >
                        <div class="flex gap-3">
                          <div class="relative h-16 w-16 overflow-hidden rounded-2xl border border-slate-200/80 bg-white shadow-sm shadow-slate-200/20 dark:border-slate-700/70 dark:bg-slate-950/60 dark:shadow-slate-900/40">
                            <.upload_entry_preview entry={entry} />
                          </div>

                          <div class="min-w-0 flex-1 space-y-3">
                            <div class="flex items-start justify-between gap-3">
                              <p class="truncate text-sm font-semibold text-slate-800 dark:text-slate-100">
                                {entry.client_name}
                              </p>
                              <button
                                type="button"
                                phx-click="cancel_media"
                                phx-value-ref={entry.ref}
                                class="inline-flex h-9 w-9 items-center justify-center rounded-2xl text-slate-500 transition hover:bg-slate-900/5 hover:text-slate-900 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:text-slate-300 dark:hover:bg-white/10 dark:hover:text-white"
                                aria-label="Remove attachment"
                              >
                                <.icon name="hero-x-mark" class="size-4" />
                              </button>
                            </div>

                            <div class="h-2 overflow-hidden rounded-full bg-slate-200/70 dark:bg-slate-700/50">
                              <div
                                class="h-full bg-slate-900 transition-all dark:bg-slate-100"
                                style={"width: #{entry.progress}%"}
                              >
                              </div>
                            </div>
                            <span class="sr-only" data-role="media-progress">{entry.progress}%</span>

                            <details
                              :if={upload_entry_kind(entry) in [:video, :audio]}
                              class="rounded-2xl border border-slate-200/80 bg-white/70 px-4 py-3 dark:border-slate-700/70 dark:bg-slate-950/50"
                            >
                              <summary class="cursor-pointer select-none text-xs font-semibold uppercase tracking-[0.2em] text-slate-600 dark:text-slate-300 list-none [&::-webkit-details-marker]:hidden">
                                Preview
                              </summary>
                              <div class="mt-3">
                                <.upload_entry_player entry={entry} />
                              </div>
                            </details>

                            <.input
                              type="text"
                              id={"media-alt-#{entry.ref}"}
                              name={"post[media_alt][#{entry.ref}]"}
                              label="Alt text"
                              value={Map.get(@media_alt, entry.ref, "")}
                              placeholder={upload_entry_description_placeholder(entry)}
                              phx-debounce="blur"
                            />

                            <p
                              :for={err <- upload_errors(@uploads.media, entry)}
                              data-role="upload-error"
                              class="text-sm text-rose-600 dark:text-rose-400"
                            >
                              {upload_error_text(err)}
                            </p>
                          </div>
                        </div>
                      </div>
                    </div>

                    <p
                      :for={err <- upload_errors(@uploads.media)}
                      data-role="upload-error"
                      class="mt-3 text-sm text-rose-600 dark:text-rose-400"
                    >
                      {upload_error_text(err)}
                    </p>
                  </div>

                  <div
                    data-role="compose-toolbar"
                    class="flex flex-wrap items-center justify-between gap-3 border-t border-slate-200/70 bg-white/70 px-4 py-3 dark:border-slate-700/70 dark:bg-slate-950/50"
                  >
                    <div class="flex items-center gap-1">
                      <label
                        data-role="compose-add-media"
                        aria-label="Add media"
                        class="relative inline-flex h-10 w-10 cursor-pointer items-center justify-center rounded-2xl text-slate-500 transition hover:bg-slate-900/5 hover:text-slate-900 focus-within:outline-none focus-within:ring-2 focus-within:ring-slate-400 dark:text-slate-300 dark:hover:bg-white/10 dark:hover:text-white"
                      >
                        <.icon name="hero-photo" class="size-5" />
                        <span class="sr-only">Add media</span>
                        <.live_file_input
                          upload={@uploads.media}
                          id="media-input"
                          class="absolute inset-0 h-full w-full cursor-pointer opacity-0"
                        />
                      </label>

                      <button
                        type="button"
                        data-role="compose-toggle-cw"
                        phx-click={
                          toggle_compose_cw_js()
                          |> JS.push("toggle_compose_cw")
                        }
                        aria-label="Content warning"
                        class={[
                          "inline-flex h-10 w-10 items-center justify-center rounded-2xl transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400",
                          @compose_cw_open? &&
                            "bg-rose-600/10 text-rose-700 hover:bg-rose-600/15 dark:bg-rose-400/10 dark:text-rose-200 dark:hover:bg-rose-400/15",
                          !@compose_cw_open? &&
                            "text-slate-500 hover:bg-slate-900/5 hover:text-slate-900 dark:text-slate-300 dark:hover:bg-white/10 dark:hover:text-white"
                        ]}
                      >
                        <.icon name="hero-exclamation-triangle" class="size-5" />
                      </button>

                      <button
                        type="button"
                        data-role="compose-toggle-options"
                        phx-click={toggle_compose_options_js()}
                        aria-label="Post options"
                        class={[
                          "inline-flex h-10 w-10 items-center justify-center rounded-2xl transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400",
                          @compose_options_open? &&
                            "bg-slate-900/5 text-slate-900 dark:bg-white/10 dark:text-white",
                          !@compose_options_open? &&
                            "text-slate-500 hover:bg-slate-900/5 hover:text-slate-900 dark:text-slate-300 dark:hover:bg-white/10 dark:hover:text-white"
                        ]}
                      >
                        <.icon name="hero-adjustments-horizontal" class="size-5" />
                      </button>

                      <button
                        type="button"
                        data-role="compose-emoji"
                        aria-label="Emoji picker"
                        disabled
                        class="inline-flex h-10 w-10 items-center justify-center rounded-2xl text-slate-400 transition dark:text-slate-600"
                      >
                        <.icon name="hero-face-smile" class="size-5" />
                      </button>
                    </div>

                    <div class="flex items-center gap-3">
                      <span
                        data-role="compose-char-counter"
                        class={[
                          "tabular-nums text-sm font-semibold",
                          remaining_chars(@form) < 0 && "text-rose-600 dark:text-rose-400",
                          remaining_chars(@form) >= 0 && "text-slate-500 dark:text-slate-400"
                        ]}
                      >
                        {remaining_chars(@form)}
                      </span>

                      <.button
                        data-role="compose-submit"
                        type="submit"
                        phx-disable-with="Posting..."
                        disabled={compose_submit_disabled?(@form, @uploads.media)}
                        size="sm"
                        class="normal-case tracking-normal"
                      >
                        Post
                      </.button>
                    </div>
                  </div>
                </div>

                <p :if={@error} data-role="compose-error" class="text-sm text-rose-500">
                  {@error}
                </p>
              </.form>
            <% else %>
              <div class="mt-6 rounded-2xl border border-slate-200/80 bg-white/70 p-4 text-sm text-slate-600 dark:border-slate-700/70 dark:bg-slate-950/50 dark:text-slate-300">
                <p>Posting requires a local account.</p>
                <div class="mt-4 flex flex-wrap items-center gap-2">
                  <.button navigate={~p"/login"} size="sm">Login</.button>
                  <.button navigate={~p"/register"} variant="secondary" size="sm">Register</.button>
                </div>
              </div>
            <% end %>
          </section>
        </:nav_top>

        <section class="space-y-4">
          <div
            id="timeline-top-sentinel"
            phx-hook="TimelineTopSentinel"
            class="h-px w-px"
            aria-hidden="true"
          >
          </div>

          <div class="flex flex-col gap-3 rounded-3xl border border-white/80 bg-white/80 p-5 shadow-lg shadow-slate-200/20 backdrop-blur dark:border-slate-700/60 dark:bg-slate-900/70 dark:shadow-slate-900/40 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <h2 class="font-display text-xl text-slate-900 dark:text-slate-100">Timeline</h2>
              <p class="mt-1 text-xs uppercase tracking-[0.3em] text-slate-500 dark:text-slate-400">
                {if @timeline == :home, do: "Home", else: "Public"}
              </p>
              <span data-role="timeline-current" class="sr-only">{@timeline}</span>
            </div>

            <div class="flex items-center gap-2">
              <%= if @current_user do %>
                <.link
                  patch={~p"/?timeline=home"}
                  class={[
                    "rounded-full px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] transition",
                    @timeline == :home &&
                      "bg-slate-900 text-white shadow-lg shadow-slate-900/20 hover:bg-slate-800 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-white",
                    @timeline != :home &&
                      "border border-slate-200/80 bg-white/70 text-slate-700 hover:-translate-y-0.5 hover:bg-white dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:hover:bg-slate-950"
                  ]}
                >
                  Home
                </.link>
              <% else %>
                <span class="rounded-full border border-slate-200/60 bg-white/40 px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-slate-400 dark:border-slate-700/60 dark:bg-slate-950/40 dark:text-slate-500">
                  Home
                </span>
              <% end %>

              <.link
                patch={~p"/?timeline=public"}
                class={[
                  "rounded-full px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] transition",
                  @timeline == :public &&
                    "bg-slate-900 text-white shadow-lg shadow-slate-900/20 hover:bg-slate-800 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-white",
                  @timeline != :public &&
                    "border border-slate-200/80 bg-white/70 text-slate-700 hover:-translate-y-0.5 hover:bg-white dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:hover:bg-slate-950"
                ]}
              >
                Public
              </.link>
            </div>
          </div>

          <% pending_count = length(@pending_posts) %>

          <button
            :if={pending_count > 0 and !@timeline_at_top?}
            type="button"
            data-role="new-posts"
            phx-click={JS.dispatch("predux:scroll-top")}
            class="sticky top-4 z-30 inline-flex w-full items-center justify-center gap-2 rounded-full border border-slate-200/80 bg-white/90 px-6 py-3 text-sm font-semibold text-slate-700 shadow-lg shadow-slate-900/10 backdrop-blur transition hover:-translate-y-0.5 hover:bg-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:border-slate-700/80 dark:bg-slate-950/70 dark:text-slate-200 dark:shadow-slate-900/40 dark:hover:bg-slate-950"
            aria-label="Scroll to new posts"
          >
            <.icon name="hero-arrow-up" class="size-4" />
            {new_posts_label(pending_count)}
          </button>

          <div id="timeline-posts" phx-update="stream" class="space-y-4">
            <div
              id="timeline-posts-empty"
              class="hidden only:block rounded-3xl border border-slate-200/80 bg-white/70 p-6 text-sm text-slate-600 shadow-sm shadow-slate-200/20 dark:border-slate-700/70 dark:bg-slate-950/50 dark:text-slate-300 dark:shadow-slate-900/30"
            >
              No posts yet.
            </div>

            <StatusCard.status_card
              :for={{id, entry} <- @streams.posts}
              id={id}
              entry={entry}
              current_user={@current_user}
            />
          </div>

          <div :if={!@posts_end?} class="flex justify-center py-2">
            <.button
              data-role="load-more"
              phx-click="load_more"
              phx-disable-with="Loading..."
              aria-label="Load more posts"
              variant="secondary"
            >
              <.icon name="hero-chevron-down" class="size-4" /> Load more
            </.button>
          </div>

          <div
            :if={!@posts_end?}
            id="timeline-bottom-sentinel"
            phx-hook="TimelineBottomSentinel"
            class="h-px w-full"
            aria-hidden="true"
          >
          </div>
        </section>

        <div
          id="compose-overlay"
          data-role="compose-overlay"
          data-state={if @compose_open?, do: "open", else: "closed"}
          class={[
            "fixed inset-0 z-40 bg-slate-950/50 backdrop-blur-sm lg:hidden",
            !@compose_open? && "hidden"
          ]}
          phx-click={close_compose_js() |> JS.push("close_compose")}
          aria-hidden={!@compose_open?}
        >
        </div>

        <button
          :if={@current_user}
          type="button"
          id="compose-open-button"
          data-role="compose-open"
          data-state={if @compose_open?, do: "hidden", else: "visible"}
          phx-click={open_compose_js() |> JS.push("open_compose")}
          class={[
            "fixed bottom-24 right-6 z-40 inline-flex h-14 w-14 items-center justify-center rounded-full bg-slate-900 text-white shadow-xl shadow-slate-900/30 transition hover:-translate-y-0.5 hover:bg-slate-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-white lg:hidden",
            @compose_open? && "hidden"
          ]}
          aria-label="Compose a new post"
        >
          <.icon name="hero-pencil-square" class="size-6" />
        </button>
      </AppShell.app_shell>

      <MediaViewer.media_viewer
        viewer={@media_viewer || %{items: [], index: 0}}
        open={@media_viewer != nil}
      />
    </Layouts.app>
    """
  end

  defp timeline_from_params(%{"timeline" => "public"}, _user), do: :public
  defp timeline_from_params(%{"timeline" => "home"}, %User{}), do: :home
  defp timeline_from_params(_params, %User{}), do: :home
  defp timeline_from_params(_params, _user), do: :public

  defp open_compose_js(js \\ %JS{}) do
    js
    |> JS.remove_class("hidden", to: "#compose-panel")
    |> JS.remove_class("hidden", to: "#compose-overlay")
    |> JS.remove_class("hidden", to: "#compose-mobile-header")
    |> JS.add_class("hidden", to: "#compose-open-button")
  end

  defp close_compose_js(js \\ %JS{}) do
    js
    |> JS.add_class("hidden lg:block", to: "#compose-panel")
    |> JS.add_class("hidden", to: "#compose-overlay")
    |> JS.add_class("hidden", to: "#compose-mobile-header")
    |> JS.remove_class("hidden", to: "#compose-open-button")
  end

  defp toggle_compose_options_js(js \\ %JS{}) do
    js
    |> JS.toggle_class("hidden", to: "#compose-options")
    |> JS.toggle_attribute({"value", "true", "false"}, to: "#compose-options-state")
  end

  defp toggle_compose_cw_js(js \\ %JS{}) do
    JS.toggle_class(js, "hidden", to: "#compose-cw")
  end

  defp list_timeline_posts(:home, %User{} = user, opts) when is_list(opts) do
    Objects.list_home_notes(user.ap_id, opts)
  end

  defp list_timeline_posts(_timeline, _user, opts) when is_list(opts) do
    Objects.list_notes(opts)
  end

  defp posts_cursor([]), do: nil

  defp posts_cursor(posts) when is_list(posts) do
    case List.last(posts) do
      %{id: id} when is_integer(id) -> id
      _ -> nil
    end
  end

  defp post_dom_id(%{object: %{id: id}}) when is_integer(id), do: "post-#{id}"
  defp post_dom_id(_post), do: Ecto.UUID.generate()

  defp include_post?(%{type: "Note"} = post, :home, home_actor_ids)
       when is_list(home_actor_ids) do
    is_binary(post.actor) and post.actor in home_actor_ids
  end

  defp include_post?(%{type: "Note"}, _timeline, _home_actor_ids), do: true
  defp include_post?(_post, _timeline, _home_actor_ids), do: false

  defp home_actor_ids(nil), do: []

  defp home_actor_ids(%User{} = user) do
    followed_actor_ids =
      user.ap_id
      |> Relationships.list_follows_by_actor()
      |> Enum.map(& &1.object)
      |> Enum.filter(&is_binary/1)

    Enum.uniq([user.ap_id | followed_actor_ids])
  end

  defp default_post_params do
    %{
      "content" => "",
      "spoiler_text" => "",
      "visibility" => "public",
      "sensitive" => "false",
      "language" => "",
      "ui_options_open" => "false",
      "media_alt" => %{}
    }
  end

  defp remaining_chars(%Phoenix.HTML.Form{} = form) do
    @compose_max_chars - String.length(content_value(form))
  end

  defp remaining_chars(_form), do: @compose_max_chars

  defp compose_max_chars, do: @compose_max_chars

  defp compose_submit_disabled?(form, upload) do
    over_limit = remaining_chars(form) < 0
    content_blank = String.trim(content_value(form)) == ""
    entries = upload_entries(upload)
    no_attachments = entries == []
    attachments_pending = Enum.any?(entries, &(!&1.done?))

    over_limit or (content_blank and no_attachments) or attachments_pending
  end

  defp content_value(%Phoenix.HTML.Form{} = form) do
    (form.params || %{})
    |> Map.get("content", "")
    |> to_string()
  end

  defp content_value(_form), do: ""

  defp upload_entries(%Phoenix.LiveView.UploadConfig{} = upload), do: upload.entries
  defp upload_entries(_upload), do: []

  defp visibility_label(visibility) when is_binary(visibility) do
    case String.trim(visibility) do
      "public" -> "Public"
      "unlisted" -> "Unlisted"
      "private" -> "Private"
      "direct" -> "Direct"
      _ -> "Public"
    end
  end

  defp visibility_label(_visibility), do: "Public"

  defp language_label(language) when is_binary(language) do
    language = String.trim(language)
    if language == "", do: "Auto", else: language
  end

  defp language_label(_language), do: "Auto"

  defp upload_error_text(:too_large), do: "File is too large."
  defp upload_error_text(:not_accepted), do: "Unsupported file type."
  defp upload_error_text(:too_many_files), do: "Too many files selected."
  defp upload_error_text(_), do: "Upload failed."

  defp notifications_count(nil), do: 0

  defp notifications_count(%User{} = user) do
    user
    |> Notifications.list_for_user(limit: 20)
    |> length()
  end

  defp truthy?(value) do
    case value do
      true -> true
      1 -> true
      "1" -> true
      "true" -> true
      _ -> false
    end
  end

  defp maybe_flush_pending_posts(socket, true) do
    pending_posts = socket.assigns.pending_posts

    if pending_posts == [] do
      assign(socket, pending_posts: [])
    else
      current_user = socket.assigns.current_user

      {socket, cursor} =
        Enum.reduce(Enum.reverse(pending_posts), {socket, socket.assigns.posts_cursor}, fn post,
                                                                                           {socket,
                                                                                            cursor} ->
          socket = stream_insert(socket, :posts, StatusVM.decorate(post, current_user), at: 0)

          cursor =
            case cursor do
              nil -> post.id
              existing -> min(existing, post.id)
            end

          {socket, cursor}
        end)

      socket
      |> assign(pending_posts: [], posts_cursor: cursor)
    end
  end

  defp maybe_flush_pending_posts(socket, _at_top?), do: socket

  defp new_posts_label(count) when is_integer(count) and count == 1, do: "1 new post"
  defp new_posts_label(count) when is_integer(count) and count > 1, do: "#{count} new posts"
  defp new_posts_label(_count), do: "New posts"

  defp refresh_post(socket, post_id) when is_integer(post_id) do
    current_user = socket.assigns.current_user

    case Objects.get(post_id) do
      %{type: "Note"} = object ->
        stream_insert(socket, :posts, StatusVM.decorate(object, current_user))

      _ ->
        socket
    end
  end
end
