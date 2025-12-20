defmodule PleromaReduxWeb.TagLive do
  use PleromaReduxWeb, :live_view

  alias PleromaRedux.Interactions
  alias PleromaRedux.Notifications
  alias PleromaRedux.Objects
  alias PleromaRedux.User
  alias PleromaRedux.Users
  alias PleromaReduxWeb.ViewModels.Status, as: StatusVM

  @page_size 20

  @impl true
  def mount(%{"tag" => tag}, session, socket) do
    current_user =
      case Map.get(session, "user_id") do
        nil -> nil
        id -> Users.get(id)
      end

    tag =
      tag
      |> to_string()
      |> String.trim()
      |> String.trim_leading("#")

    objects = Objects.list_notes_by_hashtag(tag, limit: @page_size)

    {:ok,
     socket
     |> assign(
       current_user: current_user,
       notifications_count: notifications_count(current_user),
       media_viewer: nil,
       tag: tag,
       posts: StatusVM.decorate_many(objects, current_user),
       posts_cursor: posts_cursor(objects),
       posts_end?: length(objects) < @page_size
      )}
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

  def handle_event("toggle_like", %{"id" => id}, socket) do
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)),
         {:ok, _activity} <- Interactions.toggle_like(user, post_id) do
      {:noreply, refresh_posts(socket)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to like posts.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_repost", %{"id" => id}, socket) do
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)),
         {:ok, _activity} <- Interactions.toggle_repost(user, post_id) do
      {:noreply, refresh_posts(socket)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to repost.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_reaction", %{"id" => id, "emoji" => emoji}, socket) do
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)),
         emoji when is_binary(emoji) <- to_string(emoji),
         {:ok, _activity} <- Interactions.toggle_reaction(user, post_id, emoji) do
      {:noreply, refresh_posts(socket)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to react.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("load_more_posts", _params, socket) do
    cursor = socket.assigns.posts_cursor

    cond do
      socket.assigns.posts_end? ->
        {:noreply, socket}

      is_nil(cursor) ->
        {:noreply, assign(socket, posts_end?: true)}

      true ->
        objects =
          Objects.list_notes_by_hashtag(socket.assigns.tag, limit: @page_size, max_id: cursor)

        socket =
          if objects == [] do
            assign(socket, posts_end?: true)
          else
            new_cursor = posts_cursor(objects)
            posts_end? = length(objects) < @page_size

            posts =
              socket.assigns.posts
              |> Kernel.++(StatusVM.decorate_many(objects, socket.assigns.current_user))
              |> Enum.uniq_by(& &1.object.id)

            assign(socket, posts: posts, posts_cursor: new_cursor, posts_end?: posts_end?)
          end

        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <AppShell.app_shell
        id="tag-shell"
        nav_id="tag-nav"
        main_id="tag-main"
        active={:timeline}
        current_user={@current_user}
        notifications_count={@notifications_count}
      >
        <section class="space-y-4">
          <.card class="px-5 py-4">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <.link
                navigate={timeline_href(@current_user)}
                class="inline-flex items-center gap-2 rounded-full border border-slate-200/80 bg-white/70 px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-slate-700 transition hover:-translate-y-0.5 hover:bg-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:hover:bg-slate-950"
                aria-label="Back to timeline"
              >
                <.icon name="hero-arrow-left" class="size-4" />
                Timeline
              </.link>

              <div class="text-right">
                <p data-role="tag-title" class="font-display text-lg text-slate-900 dark:text-slate-100">
                  #{to_string(@tag)}
                </p>
                <p class="mt-1 text-xs uppercase tracking-[0.3em] text-slate-500 dark:text-slate-400">
                  Hashtag
                </p>
              </div>
            </div>
          </.card>

          <div class="space-y-4">
            <div
              :if={@posts == []}
              class="rounded-3xl border border-slate-200/80 bg-white/70 p-6 text-sm text-slate-600 shadow-sm shadow-slate-200/20 dark:border-slate-700/70 dark:bg-slate-950/50 dark:text-slate-300 dark:shadow-slate-900/30"
            >
              No posts yet.
            </div>

            <StatusCard.status_card
              :for={entry <- @posts}
              id={"post-#{entry.object.id}"}
              entry={entry}
              current_user={@current_user}
            />
          </div>

          <div :if={!@posts_end?} class="flex justify-center py-2">
            <button
              type="button"
              data-role="tag-load-more"
              phx-click="load_more_posts"
              phx-disable-with="Loading..."
              class="inline-flex items-center justify-center gap-2 rounded-full border border-slate-200/80 bg-white/70 px-6 py-3 text-sm font-semibold text-slate-700 shadow-sm shadow-slate-200/20 transition hover:-translate-y-0.5 hover:bg-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:shadow-slate-900/40 dark:hover:bg-slate-950"
              aria-label="Load more posts"
            >
              <.icon name="hero-chevron-down" class="size-4" /> Load more
            </button>
          </div>
        </section>
      </AppShell.app_shell>

      <MediaViewer.media_viewer :if={@media_viewer} viewer={@media_viewer} />
    </Layouts.app>
    """
  end

  defp notifications_count(nil), do: 0

  defp notifications_count(%User{} = user) do
    user
    |> Notifications.list_for_user(limit: @page_size)
    |> length()
  end

  defp refresh_posts(socket) do
    current_user = socket.assigns.current_user

    posts =
      Enum.map(socket.assigns.posts, fn entry ->
        StatusVM.decorate(entry.object, current_user)
      end)

    assign(socket, posts: posts)
  end

  defp posts_cursor([]), do: nil

  defp posts_cursor(posts) when is_list(posts) do
    case List.last(posts) do
      %{id: id} when is_integer(id) -> id
      _ -> nil
    end
  end

  defp timeline_href(%{id: _}), do: ~p"/?timeline=home"
  defp timeline_href(_user), do: ~p"/?timeline=public"
end
