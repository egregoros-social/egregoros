defmodule PleromaReduxWeb.StatusLive do
  use PleromaReduxWeb, :live_view

  alias PleromaRedux.Interactions
  alias PleromaRedux.Media
  alias PleromaRedux.MediaStorage
  alias PleromaRedux.Notifications
  alias PleromaRedux.Objects
  alias PleromaRedux.Publish
  alias PleromaRedux.User
  alias PleromaRedux.Users
  alias PleromaReduxWeb.Endpoint
  alias PleromaReduxWeb.ViewModels.Status, as: StatusVM

  @impl true
  def mount(%{"nickname" => nickname, "uuid" => uuid} = params, session, socket) do
    current_user =
      case Map.get(session, "user_id") do
        nil -> nil
        id -> Users.get(id)
      end

    object = object_for_uuid(uuid)

    reply_open? = truthy?(Map.get(params, "reply"))
    reply_form = Phoenix.Component.to_form(%{"content" => ""}, as: :reply)

    {status_entry, ancestor_entries, descendant_entries} =
      case object do
        %{type: "Note"} = note ->
          status_entry = StatusVM.decorate(note, current_user)
          ancestors = note |> Objects.thread_ancestors() |> StatusVM.decorate_many(current_user)
          descendants = decorate_descendants(note, current_user)
          {status_entry, ancestors, descendants}

        _ ->
          {nil, [], []}
      end

    socket =
      socket
      |> assign(
        current_user: current_user,
        notifications_count: notifications_count(current_user),
        media_viewer: nil,
        nickname: nickname,
        uuid: uuid,
        status: status_entry,
        ancestors: ancestor_entries,
        descendants: descendant_entries,
        reply_open?: reply_open?,
        reply_form: reply_form,
        reply_media_alt: %{}
      )
      |> allow_upload(:reply_media,
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

  def handle_event("cancel_reply_media", %{"ref" => ref}, socket) do
    {:noreply,
     socket
     |> cancel_upload(:reply_media, ref)
     |> assign(:reply_media_alt, Map.delete(socket.assigns.reply_media_alt, ref))}
  end

  def handle_event("toggle_like", %{"id" => id}, socket) do
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)) do
      _ = Interactions.toggle_like(user, post_id)

      {:noreply, refresh_thread(socket)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to like posts.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_repost", %{"id" => id}, socket) do
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)) do
      _ = Interactions.toggle_repost(user, post_id)

      {:noreply, refresh_thread(socket)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to repost.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_reaction", %{"id" => id, "emoji" => emoji}, socket) do
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)) do
      emoji = to_string(emoji)
      _ = Interactions.toggle_reaction(user, post_id, emoji)

      {:noreply, refresh_thread(socket)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to react.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_post", %{"id" => id}, socket) do
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)),
         {:ok, _delete} <- Interactions.delete_post(user, post_id) do
      socket =
        case socket.assigns.status do
          %{object: %{id: ^post_id}} ->
            socket
            |> put_flash(:info, "Post deleted.")
            |> push_navigate(to: timeline_href(user))

          _ ->
            socket
            |> put_flash(:info, "Post deleted.")
            |> refresh_thread()
        end

      {:noreply, socket}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to delete posts.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not delete post.")}
    end
  end

  def handle_event("open_reply", _params, socket) do
    {:noreply, assign(socket, reply_open?: true)}
  end

  def handle_event("close_reply", _params, socket) do
    {:noreply, assign(socket, reply_open?: false)}
  end

  def handle_event("reply_change", %{"reply" => %{} = reply_params}, socket) do
    content = reply_params |> Map.get("content", "") |> to_string()
    media_alt = Map.get(reply_params, "media_alt", %{})

    {:noreply,
     assign(socket,
       reply_form: Phoenix.Component.to_form(%{"content" => content}, as: :reply),
       reply_media_alt: media_alt
     )}
  end

  def handle_event("create_reply", %{"reply" => %{} = reply_params}, socket) do
    content = reply_params |> Map.get("content", "") |> to_string()
    media_alt = Map.get(reply_params, "media_alt", %{})

    with %User{} = user <- socket.assigns.current_user,
         %{object: %{ap_id: in_reply_to}} <- socket.assigns.status,
         true <- is_binary(in_reply_to) and in_reply_to != "" do
      upload = socket.assigns.uploads.reply_media

      cond do
        Enum.any?(upload.entries, &(!&1.done?)) ->
          {:noreply, put_flash(socket, :error, "Wait for attachments to finish uploading.")}

        upload_has_errors?(upload) ->
          {:noreply, put_flash(socket, :error, "Remove invalid attachments before posting.")}

        true ->
          attachments =
            consume_uploaded_entries(socket, :reply_media, fn %{path: path}, entry ->
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
              {:noreply, put_flash(socket, :error, "Could not upload attachment.")}

            nil ->
              case Publish.post_note(user, content,
                     in_reply_to: in_reply_to,
                     attachments: attachments
                   ) do
                {:ok, _create} ->
                  note = socket.assigns.status.object

                  descendants = decorate_descendants(note, user)

                  {:noreply,
                   socket
                   |> put_flash(:info, "Reply posted.")
                   |> assign(
                     descendants: descendants,
                     reply_form: Phoenix.Component.to_form(%{"content" => ""}, as: :reply),
                     reply_open?: false,
                     reply_media_alt: %{}
                   )}

                {:error, :empty} ->
                  {:noreply, put_flash(socket, :error, "Reply can't be empty.")}

                _ ->
                  {:noreply, put_flash(socket, :error, "Could not post reply.")}
              end
          end
      end
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to reply.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not post reply.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <AppShell.app_shell
        id="status-shell"
        nav_id="status-nav"
        main_id="status-main"
        active={:timeline}
        current_user={@current_user}
        notifications_count={@notifications_count}
      >
        <%= if @status do %>
          <section class="space-y-4">
            <div class="flex flex-wrap items-center justify-between gap-3 rounded-3xl border border-white/80 bg-white/80 px-5 py-4 shadow-lg shadow-slate-200/20 backdrop-blur dark:border-slate-700/60 dark:bg-slate-900/70 dark:shadow-slate-900/40">
              <.link
                navigate={timeline_href(@current_user)}
                class="inline-flex items-center gap-2 rounded-full border border-slate-200/80 bg-white/70 px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-slate-700 transition hover:-translate-y-0.5 hover:bg-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:hover:bg-slate-950"
                aria-label="Back to timeline"
              >
                <.icon name="hero-arrow-left" class="size-4" /> Timeline
              </.link>

              <div class="text-right">
                <p class="font-display text-lg text-slate-900 dark:text-slate-100">Post</p>
                <p class="mt-1 text-xs uppercase tracking-[0.3em] text-slate-500 dark:text-slate-400">
                  {if @status.object.local, do: "Local status", else: "Remote status"}
                </p>
              </div>
            </div>

            <div class="space-y-4" data-role="status-thread">
              <StatusCard.status_card
                :for={entry <- @ancestors}
                id={"post-#{entry.object.id}"}
                entry={entry}
                current_user={@current_user}
              />

              <div class="rounded-3xl ring-2 ring-slate-900/10 dark:ring-white/10">
                <StatusCard.status_card
                  id={"post-#{@status.object.id}"}
                  entry={@status}
                  current_user={@current_user}
                />
              </div>

              <div
                :for={%{entry: entry, depth: depth} <- @descendants}
                data-role="thread-descendant"
                data-depth={depth}
                style={"margin-left: #{thread_indent(depth)}px"}
                class={[
                  depth > 1 && "border-l border-slate-200/60 pl-4 dark:border-slate-700/60"
                ]}
              >
                <StatusCard.status_card
                  id={"post-#{entry.object.id}"}
                  entry={entry}
                  current_user={@current_user}
                />
              </div>
            </div>

            <section
              :if={@current_user}
              class="rounded-3xl border border-white/80 bg-white/80 p-6 shadow-lg shadow-slate-200/20 backdrop-blur dark:border-slate-700/60 dark:bg-slate-900/70 dark:shadow-slate-900/40"
            >
              <.form
                for={@reply_form}
                id="reply-form"
                data-state={if @reply_open?, do: "open", else: "closed"}
                phx-change="reply_change"
                phx-submit="create_reply"
                class={["space-y-4", !@reply_open? && "hidden"]}
              >
                <div class="flex items-center justify-between gap-3">
                  <p class="text-xs font-semibold uppercase tracking-[0.3em] text-slate-500 dark:text-slate-400">
                    Reply
                  </p>
                  <button
                    type="button"
                    data-role="reply-close"
                    phx-click={close_reply_js() |> JS.push("close_reply")}
                    class="inline-flex h-9 w-9 items-center justify-center rounded-2xl text-slate-500 transition hover:bg-slate-900/5 hover:text-slate-900 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:text-slate-300 dark:hover:bg-white/10 dark:hover:text-white"
                    aria-label="Close reply composer"
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </div>

                <.input
                  field={@reply_form[:content]}
                  type="textarea"
                  label="Your reply"
                  placeholder="Write a reply…"
                  class="min-h-28"
                />

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
                      data-role="reply-add-media"
                      class="relative inline-flex w-full cursor-pointer items-center justify-center gap-2 rounded-full border border-slate-200/80 bg-white/70 px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-slate-700 transition hover:-translate-y-0.5 hover:bg-white dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:hover:bg-slate-950"
                    >
                      <.icon name="hero-photo" class="size-4" /> Add media
                      <.live_file_input
                        upload={@uploads.reply_media}
                        id="reply-media-input"
                        class="absolute inset-0 h-full w-full cursor-pointer opacity-0"
                      />
                    </label>
                  </div>

                  <div
                    class="mt-4 grid gap-3"
                    phx-drop-target={@uploads.reply_media.ref}
                    data-role="reply-media-drop"
                  >
                    <p
                      :if={@uploads.reply_media.entries == []}
                      class="rounded-2xl border border-dashed border-slate-200/80 bg-white/50 p-4 text-sm text-slate-600 dark:border-slate-700/70 dark:bg-slate-950/40 dark:text-slate-300"
                    >
                      Drop media here or use “Add media”.
                    </p>

                    <div
                      :for={entry <- @uploads.reply_media.entries}
                      id={"reply-media-entry-#{entry.ref}"}
                      data-role="reply-media-entry"
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
                              phx-click="cancel_reply_media"
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
                          <span class="sr-only" data-role="reply-media-progress">
                            {entry.progress}%
                          </span>

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
                            id={"reply-media-alt-#{entry.ref}"}
                            name={"reply[media_alt][#{entry.ref}]"}
                            label="Alt text"
                            value={Map.get(@reply_media_alt, entry.ref, "")}
                            placeholder={upload_entry_description_placeholder(entry)}
                            phx-debounce="blur"
                          />

                          <p
                            :for={err <- upload_errors(@uploads.reply_media, entry)}
                            data-role="reply-upload-error"
                            class="text-sm text-rose-600 dark:text-rose-400"
                          >
                            {upload_error_text(err)}
                          </p>
                        </div>
                      </div>
                    </div>
                  </div>

                  <p
                    :for={err <- upload_errors(@uploads.reply_media)}
                    data-role="reply-upload-error"
                    class="mt-3 text-sm text-rose-600 dark:text-rose-400"
                  >
                    {upload_error_text(err)}
                  </p>
                </section>

                <div class="flex items-center justify-end gap-3">
                  <button
                    type="submit"
                    phx-disable-with="Posting…"
                    class="inline-flex items-center gap-2 rounded-full bg-slate-900 px-6 py-3 text-sm font-semibold text-white shadow-lg shadow-slate-900/20 transition hover:-translate-y-0.5 hover:bg-slate-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-white"
                  >
                    <.icon name="hero-paper-airplane" class="size-5" /> Post reply
                  </button>
                </div>
              </.form>

              <button
                type="button"
                id="reply-open-button"
                data-role="reply-open"
                data-state={if @reply_open?, do: "hidden", else: "visible"}
                phx-click={open_reply_js() |> JS.push("open_reply")}
                class={[
                  "mt-4 inline-flex w-full items-center justify-center gap-2 rounded-full border border-slate-200/80 bg-white/70 px-6 py-3 text-sm font-semibold text-slate-700 shadow-sm shadow-slate-200/20 transition hover:-translate-y-0.5 hover:bg-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:shadow-slate-900/40 dark:hover:bg-slate-950",
                  @reply_open? && "hidden"
                ]}
              >
                <.icon name="hero-chat-bubble-left-right" class="size-5" /> Write a reply
              </button>
            </section>
          </section>
        <% else %>
          <section class="rounded-3xl border border-slate-200/80 bg-white/70 p-8 text-center shadow-sm shadow-slate-200/20 dark:border-slate-700/70 dark:bg-slate-950/50 dark:shadow-slate-900/30">
            <p class="font-display text-xl text-slate-900 dark:text-slate-100">Post not found</p>
            <p class="mt-3 text-sm text-slate-600 dark:text-slate-300">
              This status may have been deleted or was never fetched by this instance.
            </p>
            <div class="mt-6 flex justify-center">
              <.link
                navigate={timeline_href(@current_user)}
                class="inline-flex items-center gap-2 rounded-full bg-slate-900 px-6 py-3 text-sm font-semibold text-white shadow-lg shadow-slate-900/20 transition hover:-translate-y-0.5 hover:bg-slate-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-white"
              >
                <.icon name="hero-home" class="size-5" /> Go to timeline
              </.link>
            </div>
          </section>
        <% end %>
      </AppShell.app_shell>

      <MediaViewer.media_viewer
        viewer={@media_viewer || %{items: [], index: 0}}
        open={@media_viewer != nil}
      />
    </Layouts.app>
    """
  end

  defp object_for_uuid(uuid) when is_binary(uuid) do
    uuid = String.trim(uuid)

    if uuid == "" do
      nil
    else
      ap_id = Endpoint.url() <> "/objects/" <> uuid
      Objects.get_by_ap_id(ap_id)
    end
  end

  defp object_for_uuid(_uuid), do: nil

  defp notifications_count(nil), do: 0

  defp notifications_count(%User{} = user) do
    user
    |> Notifications.list_for_user(limit: 20)
    |> length()
  end

  defp upload_error_text(:too_large), do: "File is too large."
  defp upload_error_text(:not_accepted), do: "Unsupported file type."
  defp upload_error_text(:too_many_files), do: "Too many files selected."
  defp upload_error_text(_), do: "Upload failed."

  defp upload_has_errors?(%{errors: errors, entries: entries} = upload)
       when is_list(errors) and is_list(entries) do
    upload.errors != [] or
      Enum.any?(entries, fn entry ->
        not entry.valid? or upload_errors(upload, entry) != []
      end)
  end

  defp upload_has_errors?(_upload), do: false

  defp refresh_thread(socket) do
    current_user = socket.assigns.current_user

    case socket.assigns.status do
      %{object: %{type: "Note"} = note} ->
        socket
        |> assign(
          status: StatusVM.decorate(note, current_user),
          ancestors: note |> Objects.thread_ancestors() |> StatusVM.decorate_many(current_user),
          descendants: decorate_descendants(note, current_user)
        )

      _ ->
        socket
    end
  end

  defp decorate_descendants(%{} = note, current_user) do
    descendants = Objects.thread_descendants(note)
    depths = descendant_depths(note.ap_id, descendants)

    descendants
    |> StatusVM.decorate_many(current_user)
    |> Enum.zip(depths)
    |> Enum.map(fn {entry, depth} -> %{entry: entry, depth: depth} end)
  end

  defp decorate_descendants(_note, _current_user), do: []

  defp descendant_depths(root_ap_id, descendants)
       when is_binary(root_ap_id) and is_list(descendants) do
    {depths, _depth_map} =
      Enum.map_reduce(descendants, %{root_ap_id => 0}, fn descendant, depth_map ->
        parent_ap_id =
          descendant
          |> Map.get(:data, %{})
          |> Map.get("inReplyTo")
          |> in_reply_to_ap_id()

        depth = Map.get(depth_map, parent_ap_id, 0) + 1
        {depth, Map.put(depth_map, Map.get(descendant, :ap_id), depth)}
      end)

    depths
  end

  defp descendant_depths(_root_ap_id, _descendants), do: []

  defp in_reply_to_ap_id(value) when is_binary(value), do: value
  defp in_reply_to_ap_id(%{"id" => id}) when is_binary(id), do: id
  defp in_reply_to_ap_id(_), do: nil

  defp thread_indent(depth) when is_integer(depth) do
    depth
    |> Kernel.-(1)
    |> max(0)
    |> min(5)
    |> Kernel.*(24)
  end

  defp thread_indent(_depth), do: 0

  defp truthy?(value) do
    case value do
      true -> true
      1 -> true
      "1" -> true
      "true" -> true
      _ -> false
    end
  end

  defp open_reply_js(js \\ %JS{}) do
    js
    |> JS.remove_class("hidden", to: "#reply-form")
    |> JS.add_class("hidden", to: "#reply-open-button")
  end

  defp close_reply_js(js \\ %JS{}) do
    js
    |> JS.add_class("hidden", to: "#reply-form")
    |> JS.remove_class("hidden", to: "#reply-open-button")
  end

  defp timeline_href(%{id: _}), do: ~p"/?timeline=home"
  defp timeline_href(_user), do: ~p"/?timeline=public"
end
