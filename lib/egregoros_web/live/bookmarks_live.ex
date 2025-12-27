defmodule EgregorosWeb.BookmarksLive do
  use EgregorosWeb, :live_view

  import Ecto.Query, only: [from: 2]

  alias Egregoros.Interactions
  alias Egregoros.Notifications
  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Relationship
  alias Egregoros.Repo
  alias Egregoros.User
  alias Egregoros.Users
  alias EgregorosWeb.ViewModels.Status, as: StatusVM

  @page_size 20

  @impl true
  def mount(_params, session, socket) do
    current_user =
      case Map.get(session, "user_id") do
        nil -> nil
        id -> Users.get(id)
      end

    {:ok,
     socket
     |> assign(
       current_user: current_user,
       notifications_count: notifications_count(current_user),
       kind: kind_for_action(socket.assigns.live_action),
       relationship_type: relationship_type(kind_for_action(socket.assigns.live_action)),
       saved_cursor: nil,
       saved_end?: true,
       page_kicker: nil,
       page_title: nil,
       empty_message: nil
     )}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    kind = kind_for_action(socket.assigns.live_action)
    {:noreply, apply_kind(socket, kind)}
  end

  @impl true
  def handle_event("copied_link", _params, socket) do
    {:noreply, put_flash(socket, :info, "Copied link to clipboard.")}
  end

  def handle_event("toggle_like", %{"id" => id}, socket) do
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)) do
      _ = Interactions.toggle_like(user, post_id)

      socket =
        case socket.assigns.kind do
          :favourites -> refresh_or_drop_favourite(socket, post_id)
          _ -> refresh_post(socket, post_id)
        end

      {:noreply, socket}
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
        case {socket.assigns.kind, result} do
          {:bookmarks, :unbookmarked} ->
            stream_delete(socket, :saved_posts, %{object: %{id: post_id}})

          _ ->
            refresh_post(socket, post_id)
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
       |> stream_delete(:saved_posts, %{object: %{id: post_id}})}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to delete posts.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not delete post.")}
    end
  end

  def handle_event("load_more", _params, socket) do
    cursor = socket.assigns.saved_cursor

    cond do
      socket.assigns.saved_end? ->
        {:noreply, socket}

      is_nil(cursor) ->
        {:noreply, assign(socket, saved_end?: true)}

      true ->
        saved =
          list_saved_posts(socket.assigns.current_user, socket.assigns.relationship_type,
            limit: @page_size,
            max_id: cursor
          )

        socket =
          if saved == [] do
            assign(socket, saved_end?: true)
          else
            posts = saved |> Enum.map(fn {_cursor_id, object} -> object end)
            new_cursor = saved_cursor(saved)
            saved_end? = length(saved) < @page_size
            current_user = socket.assigns.current_user

            socket =
              Enum.reduce(StatusVM.decorate_many(posts, current_user), socket, fn entry, socket ->
                stream_insert(socket, :saved_posts, entry, at: -1)
              end)

            assign(socket, saved_cursor: new_cursor, saved_end?: saved_end?)
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
              <div class="min-w-0">
                <p class="text-xs uppercase tracking-[0.3em] text-slate-500 dark:text-slate-400">
                  {@page_kicker}
                </p>
                <h2 class="mt-2 truncate font-display text-2xl text-slate-900 dark:text-slate-100">
                  {@page_title}
                </h2>
              </div>

              <div class="flex items-center gap-2">
                <.link
                  patch={~p"/bookmarks"}
                  class={[
                    "rounded-full px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] transition",
                    @kind == :bookmarks &&
                      "bg-slate-900 text-white shadow-lg shadow-slate-900/20 hover:bg-slate-800 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-white",
                    @kind != :bookmarks &&
                      "border border-slate-200/80 bg-white/70 text-slate-700 hover:-translate-y-0.5 hover:bg-white dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:hover:bg-slate-950"
                  ]}
                  aria-label="View bookmarks"
                >
                  Bookmarks
                </.link>

                <.link
                  patch={~p"/favourites"}
                  class={[
                    "rounded-full px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] transition",
                    @kind == :favourites &&
                      "bg-slate-900 text-white shadow-lg shadow-slate-900/20 hover:bg-slate-800 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-white",
                    @kind != :favourites &&
                      "border border-slate-200/80 bg-white/70 text-slate-700 hover:-translate-y-0.5 hover:bg-white dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:hover:bg-slate-950"
                  ]}
                  aria-label="View favourites"
                >
                  Favourites
                </.link>
              </div>
            </div>
          </.card>

          <%= if @current_user do %>
            <div id="bookmarks-list" phx-update="stream" class="space-y-4">
              <div
                id="bookmarks-empty"
                class="hidden only:block rounded-3xl border border-slate-200/80 bg-white/70 p-6 text-sm text-slate-600 shadow-sm shadow-slate-200/20 dark:border-slate-700/70 dark:bg-slate-950/50 dark:text-slate-300 dark:shadow-slate-900/30"
              >
                {@empty_message}
              </div>

              <StatusCard.status_card
                :for={{id, entry} <- @streams.saved_posts}
                id={id}
                entry={entry}
                current_user={@current_user}
              />
            </div>

            <div :if={!@saved_end?} class="flex justify-center py-2">
              <.button
                data-role="bookmarks-load-more"
                phx-click="load_more"
                phx-disable-with="Loading..."
                aria-label="Load more saved posts"
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
                Sign in to view saved posts.
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
        if Objects.visible_to?(object, current_user) do
          stream_insert(socket, :saved_posts, StatusVM.decorate(object, current_user))
        else
          stream_delete(socket, :saved_posts, %{object: %{id: post_id}})
        end

      _ ->
        socket
    end
  end

  defp refresh_or_drop_favourite(socket, post_id) when is_integer(post_id) do
    current_user = socket.assigns.current_user

    case Objects.get(post_id) do
      %{type: "Note"} = object ->
        if Objects.visible_to?(object, current_user) do
          entry = StatusVM.decorate(object, current_user)

          if entry.liked? do
            stream_insert(socket, :saved_posts, entry)
          else
            stream_delete(socket, :saved_posts, %{object: %{id: post_id}})
          end
        else
          stream_delete(socket, :saved_posts, %{object: %{id: post_id}})
        end

      _ ->
        socket
    end
  end

  defp apply_kind(socket, kind) do
    relationship_type = relationship_type(kind)

    %{page_kicker: page_kicker, page_title: page_title, empty_message: empty_message} =
      labels(kind)

    saved = list_saved_posts(socket.assigns.current_user, relationship_type, limit: @page_size)
    posts = saved |> Enum.map(fn {_cursor_id, object} -> object end)
    cursor = saved_cursor(saved)

    socket
    |> assign(
      kind: kind,
      relationship_type: relationship_type,
      saved_cursor: cursor,
      saved_end?: length(saved) < @page_size,
      page_kicker: page_kicker,
      page_title: page_title,
      empty_message: empty_message
    )
    |> stream(:saved_posts, StatusVM.decorate_many(posts, socket.assigns.current_user),
      reset: true,
      dom_id: &post_dom_id/1
    )
  end

  defp labels(:favourites) do
    %{
      page_kicker: "Favourites",
      page_title: "Liked posts",
      empty_message: "No favourites yet."
    }
  end

  defp labels(_kind) do
    %{
      page_kicker: "Bookmarks",
      page_title: "Saved posts",
      empty_message: "No bookmarks yet."
    }
  end

  defp relationship_type(:favourites), do: "Like"
  defp relationship_type(_kind), do: "Bookmark"

  defp kind_for_action(:favourites), do: :favourites
  defp kind_for_action(_live_action), do: :bookmarks

  defp list_saved_posts(nil, _relationship_type, _opts), do: []

  defp list_saved_posts(%User{} = user, relationship_type, opts)
       when is_binary(relationship_type) and is_list(opts) do
    limit = opts |> Keyword.get(:limit, @page_size) |> normalize_limit()
    max_id = opts |> Keyword.get(:max_id) |> normalize_id()

    from(r in Relationship,
      join: o in Object,
      on: o.ap_id == r.object,
      where: r.type == ^relationship_type and r.actor == ^user.ap_id and o.type == "Note",
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

  defp saved_cursor(saved) when is_list(saved) do
    case List.last(saved) do
      {cursor_id, _object} when is_integer(cursor_id) -> cursor_id
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
