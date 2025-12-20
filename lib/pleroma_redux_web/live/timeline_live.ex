defmodule PleromaReduxWeb.TimelineLive do
  use PleromaReduxWeb, :live_view

  alias PleromaRedux.Activities.Announce
  alias PleromaRedux.Activities.EmojiReact
  alias PleromaRedux.Activities.Like
  alias PleromaRedux.Activities.Undo
  alias PleromaRedux.Federation
  alias PleromaRedux.Media
  alias PleromaRedux.MediaStorage
  alias PleromaRedux.Notifications
  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Publish
  alias PleromaRedux.Relationships
  alias PleromaRedux.Timeline
  alias PleromaRedux.User
  alias PleromaRedux.Users
  alias PleromaReduxWeb.URL
  alias PleromaReduxWeb.ViewModels.Actor, as: ActorVM
  alias PleromaReduxWeb.ViewModels.Status, as: StatusVM

  @page_size 20

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

    follow_form = Phoenix.Component.to_form(%{"handle" => ""}, as: :follow)

    posts = list_timeline_posts(timeline, current_user, limit: @page_size)

    socket =
      socket
      |> assign(
        timeline: timeline,
        home_actor_ids: home_actor_ids(current_user),
        notifications_count: notifications_count(current_user),
        compose_open?: false,
        error: nil,
        follow_error: nil,
        follow_success: nil,
        following: list_following(current_user),
        pending_posts: [],
        timeline_at_top?: true,
        media_viewer: nil,
        form: form,
        follow_form: follow_form,
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

    {:noreply,
     assign(socket,
       form: Phoenix.Component.to_form(post_params, as: :post),
       media_alt: media_alt
     )}
  end

  def handle_event("open_compose", _params, socket) do
    {:noreply, assign(socket, compose_open?: true)}
  end

  def handle_event("close_compose", _params, socket) do
    {:noreply, assign(socket, compose_open?: false)}
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
                       error: nil,
                       media_alt: %{}
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

  def handle_event("follow_remote", %{"follow" => %{"handle" => handle}}, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply,
         assign(socket, follow_error: "Register to follow people.", follow_success: nil)}

      user ->
        case Federation.follow_remote(user, handle) do
          {:ok, remote} ->
            home_actor_ids = home_actor_ids(user)

            socket =
              socket
              |> assign(
                follow_form: Phoenix.Component.to_form(%{"handle" => ""}, as: :follow),
                follow_error: nil,
                follow_success: "Following #{remote.ap_id}.",
                following: list_following(user),
                home_actor_ids: home_actor_ids
              )
              |> maybe_refresh_home_posts(user)

            {:noreply, socket}

          {:error, _reason} ->
            {:noreply, assign(socket, follow_error: "Could not follow.", follow_success: nil)}
        end
    end
  end

  def handle_event("unfollow", %{"id" => id}, socket) do
    with %User{} = user <- socket.assigns.current_user,
         {relationship_id, ""} <- Integer.parse(to_string(id)),
         %{type: "Follow", actor: actor} = relationship <- Relationships.get(relationship_id),
         true <- actor == user.ap_id,
         {:ok, _undo} <-
           Pipeline.ingest(Undo.build(user, relationship.activity_ap_id), local: true) do
      home_actor_ids = home_actor_ids(user)

      socket =
        socket
        |> assign(
          following: list_following(user),
          home_actor_ids: home_actor_ids
        )
        |> maybe_refresh_home_posts(user)

      {:noreply, socket}
    else
      nil ->
        {:noreply, assign(socket, follow_error: "Register to unfollow.", follow_success: nil)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_like", %{"id" => id}, socket) do
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)),
         %{} = post <- Objects.get(post_id),
         true <- post.type == "Note" do
      if Relationships.get_by_type_actor_object("Like", user.ap_id, post.ap_id) do
        case Relationships.get_by_type_actor_object("Like", user.ap_id, post.ap_id) do
          %{} = relationship ->
            Pipeline.ingest(Undo.build(user, relationship.activity_ap_id), local: true)

          _ ->
            {:error, :not_found}
        end
      else
        Pipeline.ingest(Like.build(user, post), local: true)
      end

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
         {post_id, ""} <- Integer.parse(to_string(id)),
         %{} = post <- Objects.get(post_id),
         true <- post.type == "Note" do
      if Relationships.get_by_type_actor_object("Announce", user.ap_id, post.ap_id) do
        case Relationships.get_by_type_actor_object("Announce", user.ap_id, post.ap_id) do
          %{} = relationship ->
            Pipeline.ingest(Undo.build(user, relationship.activity_ap_id), local: true)

          _ ->
            {:error, :not_found}
        end
      else
        Pipeline.ingest(Announce.build(user, post), local: true)
      end

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
         {post_id, ""} <- Integer.parse(to_string(id)),
         %{} = post <- Objects.get(post_id),
         true <- post.type == "Note" do
      emoji = to_string(emoji)
      relationship_type = "EmojiReact:" <> emoji

      case Relationships.get_by_type_actor_object(relationship_type, user.ap_id, post.ap_id) do
        %{} = relationship ->
          Pipeline.ingest(Undo.build(user, relationship.activity_ap_id), local: true)

        nil ->
          Pipeline.ingest(EmojiReact.build(user, post, emoji), local: true)
      end

      {:noreply, refresh_post(socket, post_id)}
    else
      nil ->
        {:noreply, assign(socket, error: "Register to react.")}

      _ ->
        {:noreply, socket}
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
        aside_id="timeline-aside"
        active={:timeline}
        current_user={@current_user}
        notifications_count={@notifications_count}
      >
        <:aside>
          <section
            id="compose-panel"
            class={[
              "rounded-3xl border border-white/80 bg-white/80 p-6 shadow-xl shadow-slate-200/40 backdrop-blur dark:border-slate-700/60 dark:bg-slate-900/70 dark:shadow-slate-900/40",
              !@compose_open? && "hidden lg:block",
              @compose_open? &&
                "fixed inset-x-4 bottom-24 z-50 max-h-[78vh] overflow-y-auto lg:static lg:inset-auto lg:bottom-auto lg:z-auto lg:max-h-none lg:overflow-visible"
            ]}
          >
            <div :if={@compose_open?} class="mb-4 flex items-center justify-between lg:hidden">
              <p class="text-xs font-semibold uppercase tracking-[0.3em] text-slate-500 dark:text-slate-400">
                Compose
              </p>
              <button
                type="button"
                data-role="compose-close"
                phx-click="close_compose"
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
                class="mt-6 space-y-4"
              >
                <.input
                  type="textarea"
                  field={@form[:content]}
                  placeholder="What's happening?"
                  rows="3"
                  phx-debounce="blur"
                />

                <details class="rounded-2xl border border-slate-200/80 bg-white/70 p-4 dark:border-slate-700/70 dark:bg-slate-950/50">
                  <summary class="cursor-pointer select-none text-sm font-semibold text-slate-700 dark:text-slate-200">
                    Options
                  </summary>
                  <div class="mt-4 grid gap-4">
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
                      field={@form[:spoiler_text]}
                      label="Content warning"
                      placeholder="Optional"
                      phx-debounce="blur"
                    />

                    <.input type="checkbox" field={@form[:sensitive]} label="Mark media as sensitive" />
                  </div>
                </details>

                <section
                  class="rounded-2xl border border-slate-200/80 bg-white/70 p-4 dark:border-slate-700/70 dark:bg-slate-950/50"
                  aria-label="Attachments"
                >
                  <div class="flex flex-col gap-3">
                    <div>
                      <p class="text-xs uppercase tracking-[0.25em] text-slate-500 dark:text-slate-400">
                        Attachments
                      </p>
                      <p class="mt-1 text-xs text-slate-500 dark:text-slate-400">
                        Images, video, audio — up to 10MB
                      </p>
                    </div>

                    <label
                      data-role="compose-add-media"
                      class="relative inline-flex w-full cursor-pointer items-center justify-center gap-2 rounded-full border border-slate-200/80 bg-white/70 px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-slate-700 transition hover:-translate-y-0.5 hover:bg-white dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:hover:bg-slate-950"
                    >
                      <.icon name="hero-photo" class="size-4" /> Add media
                      <.live_file_input
                        upload={@uploads.media}
                        id="media-input"
                        class="absolute inset-0 h-full w-full cursor-pointer opacity-0"
                      />
                    </label>
                  </div>

                  <div
                    class="mt-4 grid gap-3"
                    phx-drop-target={@uploads.media.ref}
                    data-role="media-drop"
                  >
                    <p
                      :if={@uploads.media.entries == []}
                      class="rounded-2xl border border-dashed border-slate-200/80 bg-white/50 p-4 text-sm text-slate-600 dark:border-slate-700/70 dark:bg-slate-950/40 dark:text-slate-300"
                    >
                      Drop media here or use “Add media”.
                    </p>

                    <div
                      :for={entry <- @uploads.media.entries}
                      id={"media-entry-#{entry.ref}"}
                      data-role="media-entry"
                      class="rounded-2xl border border-slate-200/80 bg-white/60 p-3 shadow-sm shadow-slate-200/20 dark:border-slate-700/70 dark:bg-slate-950/50 dark:shadow-slate-900/40"
                    >
                      <div class="flex gap-3">
                        <div class="relative h-16 w-16 overflow-hidden rounded-2xl border border-slate-200/80 bg-white shadow-sm shadow-slate-200/20 dark:border-slate-700/70 dark:bg-slate-950/60 dark:shadow-slate-900/40">
                          <%= if image_upload?(entry) do %>
                            <.live_img_preview entry={entry} class="h-full w-full object-cover" />
                          <% else %>
                            <div class="flex h-full w-full items-center justify-center bg-slate-900/5 text-slate-500 dark:bg-white/5 dark:text-slate-300">
                              <.icon name={media_upload_icon(entry)} class="size-7" />
                            </div>
                          <% end %>
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

                          <.input
                            type="text"
                            id={"media-alt-#{entry.ref}"}
                            name={"post[media_alt][#{entry.ref}]"}
                            label="Alt text"
                            value={Map.get(@media_alt, entry.ref, "")}
                            placeholder="Describe the image for screen readers"
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
                </section>

                <div class="flex flex-wrap items-center justify-between gap-3">
                  <p :if={@error} data-role="compose-error" class="text-sm text-rose-500">
                    {@error}
                  </p>
                  <div class="ml-auto flex items-center gap-3">
                    <span class="text-xs uppercase tracking-[0.25em] text-slate-400 dark:text-slate-500">
                      {@current_user.nickname}
                    </span>
                    <.button type="submit" phx-disable-with="Posting...">Post</.button>
                  </div>
                </div>
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

          <section
            id="follow-panel"
            class="hidden rounded-3xl border border-white/80 bg-white/80 p-6 shadow-lg shadow-slate-200/30 backdrop-blur dark:border-slate-700/60 dark:bg-slate-900/70 dark:shadow-slate-900/50 lg:block"
          >
            <div class="flex items-center justify-between gap-4">
              <div>
                <p class="text-xs uppercase tracking-[0.3em] text-slate-500 dark:text-slate-400">
                  Follow
                </p>
                <h2 class="mt-2 font-display text-xl text-slate-900 dark:text-slate-100">
                  Find someone
                </h2>
              </div>
              <p class="hidden text-right text-xs text-slate-500 dark:text-slate-400 sm:block">
                alice@remote.example
              </p>
            </div>

            <%= if @current_user do %>
              <.form
                for={@follow_form}
                id="follow-form"
                phx-submit="follow_remote"
                class="mt-6 flex flex-col gap-4 sm:flex-row sm:items-end"
              >
                <div class="flex-1">
                  <.input
                    type="text"
                    field={@follow_form[:handle]}
                    label="Handle"
                    placeholder="bob@remote.example"
                  />
                </div>

                <.button type="submit" phx-disable-with="Following..." variant="secondary">
                  Follow
                </.button>
              </.form>

              <p :if={@follow_error} class="mt-3 text-sm text-rose-500">{@follow_error}</p>
              <p :if={@follow_success} class="mt-3 text-sm text-emerald-600 dark:text-emerald-400">
                {@follow_success}
              </p>
            <% else %>
              <div class="mt-6 rounded-2xl border border-slate-200/80 bg-white/70 p-4 text-sm text-slate-600 dark:border-slate-700/70 dark:bg-slate-950/50 dark:text-slate-300">
                Following requires a local account.
              </div>
            <% end %>
          </section>

          <section
            :if={@current_user}
            id="following-panel"
            class="hidden rounded-3xl border border-white/80 bg-white/80 p-6 shadow-lg shadow-slate-200/30 backdrop-blur dark:border-slate-700/60 dark:bg-slate-900/70 dark:shadow-slate-900/50 lg:block"
          >
            <div class="flex items-center justify-between">
              <h3 class="text-xs uppercase tracking-[0.3em] text-slate-500 dark:text-slate-400">
                Following
              </h3>
              <span class="text-xs text-slate-400 dark:text-slate-500">
                {length(@following)}
              </span>
            </div>

            <div class="mt-4 space-y-2">
              <%= for entry <- @following do %>
                <div
                  id={"following-#{entry.relationship.id}"}
                  class="flex items-center justify-between gap-3 rounded-2xl border border-slate-200/80 bg-white/70 px-4 py-3 text-sm shadow-sm shadow-slate-200/20 backdrop-blur dark:border-slate-700/70 dark:bg-slate-950/60 dark:shadow-slate-900/40"
                >
                  <div class="flex min-w-0 items-center gap-3">
                    <div class="shrink-0">
                      <%= if entry.target &&
                             is_binary(entry.target.avatar_url) and
                             entry.target.avatar_url != "" do %>
                        <img
                          src={URL.absolute(entry.target.avatar_url)}
                          alt={entry.target.nickname}
                          class="h-9 w-9 rounded-xl border border-slate-200/80 bg-white object-cover shadow-sm shadow-slate-200/40 dark:border-slate-700/60 dark:bg-slate-950/60 dark:shadow-slate-900/40"
                          loading="lazy"
                        />
                      <% else %>
                        <div class="flex h-9 w-9 items-center justify-center rounded-xl border border-slate-200/80 bg-white/70 text-xs font-semibold text-slate-700 shadow-sm shadow-slate-200/30 dark:border-slate-700/60 dark:bg-slate-950/60 dark:text-slate-200 dark:shadow-slate-900/40">
                          {if entry.target,
                            do: avatar_initial(entry.target.name || entry.target.nickname),
                            else: "?"}
                        </div>
                      <% end %>
                    </div>

                    <div class="min-w-0">
                      <p class="truncate font-semibold text-slate-900 dark:text-slate-100">
                        {if entry.target,
                          do: entry.target.name || entry.target.nickname,
                          else: entry.relationship.object}
                      </p>
                      <p class="truncate text-xs text-slate-500 dark:text-slate-400">
                        {if entry.target,
                          do: ActorVM.handle(entry.target, entry.target.ap_id),
                          else: entry.relationship.object}
                      </p>
                    </div>
                  </div>

                  <button
                    type="button"
                    data-role="unfollow"
                    phx-click="unfollow"
                    phx-value-id={entry.relationship.id}
                    phx-disable-with="Unfollowing..."
                    class="shrink-0 rounded-full border border-slate-200/80 bg-white/70 px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-slate-700 transition hover:-translate-y-0.5 hover:bg-white dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:hover:bg-slate-950"
                  >
                    Unfollow
                  </button>
                </div>
              <% end %>

              <p :if={@following == []} class="text-sm text-slate-500 dark:text-slate-400">
                Follow someone to start building your home graph.
              </p>
            </div>
          </section>
        </:aside>

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
            <button
              type="button"
              data-role="load-more"
              phx-click="load_more"
              phx-disable-with="Loading..."
              class="inline-flex items-center justify-center gap-2 rounded-full border border-slate-200/80 bg-white/70 px-6 py-3 text-sm font-semibold text-slate-700 shadow-sm shadow-slate-200/20 transition hover:-translate-y-0.5 hover:bg-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:shadow-slate-900/40 dark:hover:bg-slate-950"
              aria-label="Load more posts"
            >
              <.icon name="hero-chevron-down" class="size-4" /> Load more
            </button>
          </div>
        </section>

        <div
          :if={@compose_open?}
          id="compose-overlay"
          class="fixed inset-0 z-40 bg-slate-950/50 backdrop-blur-sm lg:hidden"
          phx-click="close_compose"
          aria-hidden="true"
        >
        </div>

        <button
          :if={@current_user && !@compose_open?}
          type="button"
          data-role="compose-open"
          phx-click="open_compose"
          class="fixed bottom-24 right-6 z-40 inline-flex h-14 w-14 items-center justify-center rounded-full bg-slate-900 text-white shadow-xl shadow-slate-900/30 transition hover:-translate-y-0.5 hover:bg-slate-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-white lg:hidden"
          aria-label="Compose a new post"
        >
          <.icon name="hero-pencil-square" class="size-6" />
        </button>
      </AppShell.app_shell>

      <MediaViewer.media_viewer :if={@media_viewer} viewer={@media_viewer} />
    </Layouts.app>
    """
  end

  defp list_following(nil), do: []

  defp list_following(%User{} = user) do
    user.ap_id
    |> Relationships.list_follows_by_actor()
    |> Enum.sort_by(& &1.updated_at, :desc)
    |> Enum.map(fn follow ->
      %{relationship: follow, target: Users.get_by_ap_id(follow.object)}
    end)
  end

  defp timeline_from_params(%{"timeline" => "public"}, _user), do: :public
  defp timeline_from_params(%{"timeline" => "home"}, %User{}), do: :home
  defp timeline_from_params(_params, %User{}), do: :home
  defp timeline_from_params(_params, _user), do: :public

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

  defp maybe_refresh_home_posts(%{assigns: %{timeline: :home}} = socket, %User{} = user) do
    posts = list_timeline_posts(:home, user, limit: @page_size)

    socket
    |> assign(
      posts_cursor: posts_cursor(posts),
      posts_end?: length(posts) < @page_size
    )
    |> stream(:posts, StatusVM.decorate_many(posts, user), reset: true, dom_id: &post_dom_id/1)
  end

  defp maybe_refresh_home_posts(socket, _user), do: socket

  defp default_post_params do
    %{
      "content" => "",
      "spoiler_text" => "",
      "visibility" => "public",
      "sensitive" => "false",
      "language" => "",
      "media_alt" => %{}
    }
  end

  defp upload_error_text(:too_large), do: "File is too large."
  defp upload_error_text(:not_accepted), do: "Unsupported file type."
  defp upload_error_text(:too_many_files), do: "Too many files selected."
  defp upload_error_text(_), do: "Upload failed."

  defp image_upload?(%{client_type: type}) when is_binary(type) do
    String.starts_with?(type, "image/")
  end

  defp image_upload?(_entry), do: false

  defp media_upload_icon(%{client_type: type}) when is_binary(type) do
    cond do
      String.starts_with?(type, "video/") -> "hero-film"
      String.starts_with?(type, "audio/") -> "hero-musical-note"
      true -> "hero-paper-clip"
    end
  end

  defp media_upload_icon(_entry), do: "hero-paper-clip"

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
                                                                                        {socket, cursor} ->
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

  defp avatar_initial(name) when is_binary(name) do
    name = String.trim(name)

    case String.first(name) do
      nil -> "?"
      letter -> String.upcase(letter)
    end
  end

  defp avatar_initial(_), do: "?"
end
