defmodule PleromaReduxWeb.BookmarksLive do
  use PleromaReduxWeb, :live_view

  import Ecto.Query, only: [from: 2]

  alias PleromaRedux.Interactions
  alias PleromaRedux.Notifications
  alias PleromaRedux.Object
  alias PleromaRedux.Objects
  alias PleromaRedux.Relationship
  alias PleromaRedux.Repo
  alias PleromaRedux.User
  alias PleromaRedux.Users
  alias PleromaReduxWeb.ViewModels.Status, as: StatusVM

  @page_size 20

  @impl true
  def mount(_params, session, socket) do
    current_user =
      case Map.get(session, "user_id") do
        nil -> nil
        id -> Users.get(id)
      end

    bookmarks = list_bookmarks(current_user, limit: @page_size)
    posts = bookmarks |> Enum.map(fn {_bookmark_id, object} -> object end)

    {:ok,
     socket
     |> assign(
       current_user: current_user,
       notifications_count: notifications_count(current_user),
       bookmarks_cursor: bookmarks_cursor(bookmarks),
       bookmarks_end?: length(bookmarks) < @page_size
     )
     |> stream(:bookmarks, StatusVM.decorate_many(posts, current_user), dom_id: &post_dom_id/1)}
  end

  @impl true
  def handle_event("copied_link", _params, socket) do
    {:noreply, put_flash(socket, :info, "Copied link to clipboard.")}
  end

  def handle_event("toggle_like", %{"id" => id}, socket) do
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)) do
      _ = Interactions.toggle_like(user, post_id)
      {:noreply, refresh_post(socket, post_id)}
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
      {:noreply, refresh_post(socket, post_id)}
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
         emoji when is_binary(emoji) <- to_string(emoji) do
      _ = Interactions.toggle_reaction(user, post_id, emoji)
      {:noreply, refresh_post(socket, post_id)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to react.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_bookmark", %{"id" => id}, socket) do
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)),
         {:ok, result} <- Interactions.toggle_bookmark(user, post_id) do
      socket =
        case result do
          :unbookmarked -> stream_delete(socket, :bookmarks, %{object: %{id: post_id}})
          _ -> refresh_post(socket, post_id)
        end

      {:noreply, socket}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to bookmark posts.")}

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
       |> stream_delete(:bookmarks, %{object: %{id: post_id}})}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to delete posts.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not delete post.")}
    end
  end

  def handle_event("load_more", _params, socket) do
    cursor = socket.assigns.bookmarks_cursor

    cond do
      socket.assigns.bookmarks_end? ->
        {:noreply, socket}

      is_nil(cursor) ->
        {:noreply, assign(socket, bookmarks_end?: true)}

      true ->
        bookmarks =
          list_bookmarks(socket.assigns.current_user,
            limit: @page_size,
            max_id: cursor
          )

        socket =
          if bookmarks == [] do
            assign(socket, bookmarks_end?: true)
          else
            posts = bookmarks |> Enum.map(fn {_bookmark_id, object} -> object end)
            new_cursor = bookmarks_cursor(bookmarks)
            bookmarks_end? = length(bookmarks) < @page_size
            current_user = socket.assigns.current_user

            socket =
              Enum.reduce(StatusVM.decorate_many(posts, current_user), socket, fn entry, socket ->
                stream_insert(socket, :bookmarks, entry, at: -1)
              end)

            assign(socket, bookmarks_cursor: new_cursor, bookmarks_end?: bookmarks_end?)
          end

        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <AppShell.app_shell
        id="bookmarks-shell"
        nav_id="bookmarks-nav"
        main_id="bookmarks-main"
        active={:bookmarks}
        current_user={@current_user}
        notifications_count={@notifications_count}
      >
        <section class="space-y-4">
          <.card class="p-6">
            <div class="flex items-center justify-between gap-4">
              <div>
                <p class="text-xs uppercase tracking-[0.3em] text-slate-500 dark:text-slate-400">
                  Bookmarks
                </p>
                <h2 class="mt-2 font-display text-2xl text-slate-900 dark:text-slate-100">
                  Saved posts
                </h2>
              </div>
            </div>
          </.card>

          <%= if @current_user do %>
            <div id="bookmarks-list" phx-update="stream" class="space-y-4">
              <div
                id="bookmarks-empty"
                class="hidden only:block rounded-3xl border border-slate-200/80 bg-white/70 p-6 text-sm text-slate-600 shadow-sm shadow-slate-200/20 dark:border-slate-700/70 dark:bg-slate-950/50 dark:text-slate-300 dark:shadow-slate-900/30"
              >
                No bookmarks yet.
              </div>

              <StatusCard.status_card
                :for={{id, entry} <- @streams.bookmarks}
                id={id}
                entry={entry}
                current_user={@current_user}
              />
            </div>

            <div :if={!@bookmarks_end?} class="flex justify-center py-2">
              <.button
                data-role="bookmarks-load-more"
                phx-click="load_more"
                phx-disable-with="Loading..."
                aria-label="Load more bookmarks"
                variant="secondary"
              >
                <.icon name="hero-chevron-down" class="size-4" /> Load more
              </.button>
            </div>
          <% else %>
            <.card class="p-6">
              <p
                data-role="bookmarks-auth-required"
                class="text-sm text-slate-600 dark:text-slate-300"
              >
                Sign in to view bookmarks.
              </p>
              <div class="mt-4 flex flex-wrap items-center gap-2">
                <.button navigate={~p"/login"} size="sm">Login</.button>
                <.button navigate={~p"/register"} size="sm" variant="secondary">Register</.button>
              </div>
            </.card>
          <% end %>
        </section>
      </AppShell.app_shell>

      <MediaViewer.media_viewer
        viewer={%{items: [], index: 0}}
        open={false}
      />
    </Layouts.app>
    """
  end

  defp refresh_post(socket, post_id) when is_integer(post_id) do
    current_user = socket.assigns.current_user

    case Objects.get(post_id) do
      %{type: "Note"} = object ->
        stream_insert(socket, :bookmarks, StatusVM.decorate(object, current_user))

      _ ->
        socket
    end
  end

  defp list_bookmarks(nil, _opts), do: []

  defp list_bookmarks(%User{} = user, opts) when is_list(opts) do
    limit = opts |> Keyword.get(:limit, @page_size) |> normalize_limit()
    max_id = opts |> Keyword.get(:max_id) |> normalize_id()

    from(r in Relationship,
      join: o in Object,
      on: o.ap_id == r.object,
      where: r.type == "Bookmark" and r.actor == ^user.ap_id and o.type == "Note",
      order_by: [desc: r.id],
      limit: ^limit,
      select: {r.id, o}
    )
    |> maybe_where_max_id(max_id)
    |> Repo.all()
  end

  defp maybe_where_max_id(query, max_id) when is_integer(max_id) and max_id > 0 do
    from([r, _o] in query, where: r.id < ^max_id)
  end

  defp maybe_where_max_id(query, _max_id), do: query

  defp bookmarks_cursor(bookmarks) when is_list(bookmarks) do
    case List.last(bookmarks) do
      {bookmark_id, _object} when is_integer(bookmark_id) -> bookmark_id
      _ -> nil
    end
  end

  defp post_dom_id(%{object: %{id: id}}) when is_integer(id), do: "post-#{id}"
  defp post_dom_id(_post), do: Ecto.UUID.generate()

  defp normalize_limit(limit) when is_integer(limit) do
    limit
    |> max(1)
    |> min(40)
  end

  defp normalize_limit(_), do: @page_size

  defp normalize_id(nil), do: nil
  defp normalize_id(id) when is_integer(id) and id > 0, do: id

  defp normalize_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} when int > 0 -> int
      _ -> nil
    end
  end

  defp normalize_id(_), do: nil

  defp notifications_count(nil), do: 0

  defp notifications_count(%User{} = user) do
    user
    |> Notifications.list_for_user(limit: 20)
    |> length()
  end
end
