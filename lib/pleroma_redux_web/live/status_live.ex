defmodule PleromaReduxWeb.StatusLive do
  use PleromaReduxWeb, :live_view

  alias PleromaRedux.Interactions
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
          descendants = note |> Objects.thread_descendants() |> StatusVM.decorate_many(current_user)
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
        reply_form: reply_form
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

  def handle_event("open_reply", _params, socket) do
    {:noreply, assign(socket, reply_open?: true)}
  end

  def handle_event("close_reply", _params, socket) do
    {:noreply, assign(socket, reply_open?: false)}
  end

  def handle_event("reply_change", %{"reply" => %{} = reply_params}, socket) do
    content = reply_params |> Map.get("content", "") |> to_string()
    {:noreply, assign(socket, reply_form: Phoenix.Component.to_form(%{"content" => content}, as: :reply))}
  end

  def handle_event("create_reply", %{"reply" => %{} = reply_params}, socket) do
    content = reply_params |> Map.get("content", "") |> to_string()

    with %User{} = user <- socket.assigns.current_user,
         %{object: %{ap_id: in_reply_to}} <- socket.assigns.status,
         true <- is_binary(in_reply_to) and in_reply_to != "" do
      case Publish.post_note(user, content, in_reply_to: in_reply_to) do
        {:ok, _create} ->
          note = socket.assigns.status.object

          descendants =
            note
            |> Objects.thread_descendants()
            |> StatusVM.decorate_many(user)

          {:noreply,
           socket
           |> put_flash(:info, "Reply posted.")
           |> assign(
             descendants: descendants,
             reply_form: Phoenix.Component.to_form(%{"content" => ""}, as: :reply),
             reply_open?: false
           )}

        {:error, :empty} ->
          {:noreply, put_flash(socket, :error, "Reply can't be empty.")}

        _ ->
          {:noreply, put_flash(socket, :error, "Could not post reply.")}
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
                <.icon name="hero-arrow-left" class="size-4" />
                Timeline
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

              <StatusCard.status_card
                :for={entry <- @descendants}
                id={"post-#{entry.object.id}"}
                entry={entry}
                current_user={@current_user}
              />
            </div>

            <section :if={@current_user} class="rounded-3xl border border-white/80 bg-white/80 p-6 shadow-lg shadow-slate-200/20 backdrop-blur dark:border-slate-700/60 dark:bg-slate-900/70 dark:shadow-slate-900/40">
              <%= if @reply_open? do %>
                <.form
                  for={@reply_form}
                  id="reply-form"
                  phx-change="reply_change"
                  phx-submit="create_reply"
                  class="space-y-4"
                >
                  <div class="flex items-center justify-between gap-3">
                    <p class="text-xs font-semibold uppercase tracking-[0.3em] text-slate-500 dark:text-slate-400">
                      Reply
                    </p>
                    <button
                      type="button"
                      phx-click="close_reply"
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
              <% else %>
                <button
                  type="button"
                  data-role="reply-open"
                  phx-click="open_reply"
                  class="inline-flex w-full items-center justify-center gap-2 rounded-full border border-slate-200/80 bg-white/70 px-6 py-3 text-sm font-semibold text-slate-700 shadow-sm shadow-slate-200/20 transition hover:-translate-y-0.5 hover:bg-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:shadow-slate-900/40 dark:hover:bg-slate-950"
                >
                  <.icon name="hero-chat-bubble-left-right" class="size-5" />
                  Write a reply
                </button>
              <% end %>
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
                <.icon name="hero-home" class="size-5" />
                Go to timeline
              </.link>
            </div>
          </section>
        <% end %>
      </AppShell.app_shell>

      <MediaViewer.media_viewer :if={@media_viewer} viewer={@media_viewer} />
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

  defp refresh_thread(socket) do
    current_user = socket.assigns.current_user

    case socket.assigns.status do
      %{object: %{type: "Note"} = note} ->
        socket
        |> assign(
          status: StatusVM.decorate(note, current_user),
          ancestors: note |> Objects.thread_ancestors() |> StatusVM.decorate_many(current_user),
          descendants: note |> Objects.thread_descendants() |> StatusVM.decorate_many(current_user)
        )

      _ ->
        socket
    end
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

  defp timeline_href(%{id: _}), do: ~p"/?timeline=home"
  defp timeline_href(_user), do: ~p"/?timeline=public"
end
