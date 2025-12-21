defmodule PleromaReduxWeb.ProfileLive do
  use PleromaReduxWeb, :live_view

  alias PleromaRedux.Activities.Follow
  alias PleromaRedux.Activities.Undo
  alias PleromaRedux.Interactions
  alias PleromaRedux.Notifications
  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Relationships
  alias PleromaRedux.User
  alias PleromaRedux.Users
  alias PleromaReduxWeb.ProfilePaths
  alias PleromaReduxWeb.URL
  alias PleromaReduxWeb.ViewModels.Actor, as: ActorVM
  alias PleromaReduxWeb.ViewModels.Status, as: StatusVM

  @page_size 20

  @impl true
  def mount(%{"nickname" => handle}, session, socket) do
    current_user =
      case Map.get(session, "user_id") do
        nil -> nil
        id -> Users.get(id)
      end

    profile_user =
      handle
      |> to_string()
      |> String.trim()
      |> Users.get_by_handle()

    profile_handle =
      case profile_user do
        %User{} = user -> ActorVM.handle(user, user.ap_id)
        _ -> nil
      end

    posts =
      case profile_user do
        %User{} = user -> Objects.list_notes_by_actor(user.ap_id, limit: @page_size)
        _ -> []
      end

    follow_relationship =
      follow_relationship(current_user, profile_user)

    {:ok,
     socket
     |> assign(
       current_user: current_user,
       profile_user: profile_user,
       profile_handle: profile_handle,
       notifications_count: notifications_count(current_user),
       media_viewer: nil,
       follow_relationship: follow_relationship,
       posts_count: count_posts(profile_user),
       followers_count: count_followers(profile_user),
       following_count: count_following(profile_user),
       posts_cursor: posts_cursor(posts),
       posts_end?: length(posts) < @page_size
     )
     |> stream(:posts, StatusVM.decorate_many(posts, current_user), dom_id: &post_dom_id/1)}
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

  def handle_event("follow", _params, socket) do
    with %User{} = viewer <- socket.assigns.current_user,
         %User{} = profile_user <- socket.assigns.profile_user,
         true <- viewer.id != profile_user.id,
         nil <- Relationships.get_by_type_actor_object("Follow", viewer.ap_id, profile_user.ap_id),
         {:ok, _follow} <- Pipeline.ingest(Follow.build(viewer, profile_user), local: true) do
      relationship =
        Relationships.get_by_type_actor_object("Follow", viewer.ap_id, profile_user.ap_id)

      {:noreply,
       socket
       |> put_flash(:info, "Following #{profile_user.nickname}.")
       |> assign(
         follow_relationship: relationship,
         followers_count: count_followers(profile_user)
       )}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to follow people.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("unfollow", _params, socket) do
    with %User{} = viewer <- socket.assigns.current_user,
         %User{} = profile_user <- socket.assigns.profile_user,
         %{} = relationship <- socket.assigns.follow_relationship,
         {:ok, _undo} <-
           Pipeline.ingest(Undo.build(viewer, relationship.activity_ap_id), local: true) do
      {:noreply,
       socket
       |> put_flash(:info, "Unfollowed #{profile_user.nickname}.")
       |> assign(
         follow_relationship: nil,
         followers_count: count_followers(profile_user)
       )}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to unfollow people.")}

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
        posts =
          case socket.assigns.profile_user do
            %User{} = user ->
              Objects.list_notes_by_actor(user.ap_id, limit: @page_size, max_id: cursor)

            _ ->
              []
          end

        socket =
          if posts == [] do
            assign(socket, posts_end?: true)
          else
            new_cursor = posts_cursor(posts)
            posts_end? = length(posts) < @page_size
            viewer = socket.assigns.current_user

            socket =
              Enum.reduce(StatusVM.decorate_many(posts, viewer), socket, fn entry, socket ->
                stream_insert(socket, :posts, entry, at: -1)
              end)

            assign(socket, posts_cursor: new_cursor, posts_end?: posts_end?)
          end

        {:noreply, socket}
    end
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
         {post_id, ""} <- Integer.parse(to_string(id)) do
      emoji = to_string(emoji)
      _ = Interactions.toggle_reaction(user, post_id, emoji)

      {:noreply, refresh_post(socket, post_id)}
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
      profile_user = socket.assigns.profile_user

      socket =
        socket
        |> put_flash(:info, "Post deleted.")
        |> stream_delete(:posts, %{object: %{id: post_id}})

      socket =
        case profile_user do
          %User{} -> assign(socket, posts_count: count_posts(profile_user))
          _ -> socket
        end

      {:noreply, socket}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to delete posts.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not delete post.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <AppShell.app_shell
        id="profile-shell"
        nav_id="profile-nav"
        main_id="profile-main"
        active={:profile}
        current_user={@current_user}
        notifications_count={@notifications_count}
      >
        <%= if @profile_user do %>
          <section class="space-y-6">
            <.card class="overflow-hidden p-0" data_role="profile-header">
              <div
                data-role="profile-banner"
                class="relative h-32 bg-gradient-to-r from-slate-900 via-slate-800 to-rose-700 dark:from-slate-950 dark:via-slate-900 dark:to-rose-600 sm:h-36"
              >
                <img
                  :if={is_binary(@profile_user.banner_url) and @profile_user.banner_url != ""}
                  data-role="profile-banner-image"
                  src={URL.absolute(@profile_user.banner_url, @profile_user.ap_id)}
                  alt=""
                  class="absolute inset-0 h-full w-full object-cover"
                  loading="lazy"
                />
                <div class="absolute inset-0 bg-gradient-to-t from-slate-950/70 via-slate-950/10 to-transparent">
                </div>
                <div class="pointer-events-none absolute inset-0 opacity-70 mix-blend-overlay">
                  <div class="absolute -left-14 -top-10 h-40 w-40 rounded-full bg-white/10 blur-2xl">
                  </div>
                  <div class="absolute -right-12 bottom-0 h-32 w-32 rounded-full bg-white/10 blur-2xl">
                  </div>
                </div>

                <div class="absolute -bottom-10 left-6">
                  <.avatar
                    data_role="profile-avatar"
                    size="xl"
                    name={@profile_user.name || @profile_user.nickname}
                    src={URL.absolute(@profile_user.avatar_url, @profile_user.ap_id)}
                    class="ring-4 ring-white shadow-lg shadow-slate-900/10 dark:ring-slate-900 dark:shadow-slate-950/40"
                  />
                </div>
              </div>

              <div class="px-6 pb-6 pt-14 sm:pt-16">
                <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
                  <div class="min-w-0">
                    <h2
                      data-role="profile-name"
                      class="truncate font-display text-2xl text-slate-900 dark:text-slate-100"
                    >
                      {@profile_user.name || @profile_user.nickname}
                    </h2>
                    <p
                      data-role="profile-handle"
                      class="mt-1 truncate text-sm text-slate-500 dark:text-slate-400"
                    >
                      {@profile_handle}
                    </p>
                  </div>

                  <div class="flex flex-wrap items-center gap-2">
                    <%= if @current_user && @current_user.id != @profile_user.id do %>
                      <%= if @follow_relationship do %>
                        <button
                          type="button"
                          data-role="profile-unfollow"
                          phx-click="unfollow"
                          phx-disable-with="Unfollowing..."
                          class="inline-flex items-center justify-center rounded-full border border-slate-200/80 bg-white/70 px-5 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-slate-700 shadow-sm shadow-slate-200/20 transition hover:-translate-y-0.5 hover:bg-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:shadow-slate-900/40 dark:hover:bg-slate-950"
                        >
                          Unfollow
                        </button>
                      <% else %>
                        <button
                          type="button"
                          data-role="profile-follow"
                          phx-click="follow"
                          phx-disable-with="Following..."
                          class="inline-flex items-center justify-center rounded-full bg-slate-900 px-5 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-white shadow-lg shadow-slate-900/25 transition hover:-translate-y-0.5 hover:bg-slate-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-white"
                        >
                          Follow
                        </button>
                      <% end %>
                    <% end %>
                  </div>
                </div>

                <p
                  :if={is_binary(@profile_user.bio) and @profile_user.bio != ""}
                  class="mt-5 max-w-prose text-sm text-slate-700 dark:text-slate-200"
                >
                  {@profile_user.bio}
                </p>

                <div class="mt-6 grid grid-cols-3 gap-3 sm:max-w-md">
                  <.stat value={@posts_count} label="Posts" />

                  <.link
                    navigate={ProfilePaths.followers_path(@profile_user)}
                    class="block focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400"
                  >
                    <.stat value={@followers_count} label="Followers" />
                  </.link>

                  <.link
                    navigate={ProfilePaths.following_path(@profile_user)}
                    class="block focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400"
                  >
                    <.stat value={@following_count} label="Following" />
                  </.link>
                </div>
              </div>
            </.card>

            <section class="space-y-4">
              <div class="flex flex-col gap-3 rounded-3xl border border-white/80 bg-white/80 p-5 shadow-lg shadow-slate-200/20 backdrop-blur dark:border-slate-700/60 dark:bg-slate-900/70 dark:shadow-slate-900/40 sm:flex-row sm:items-center sm:justify-between">
                <div>
                  <h3 class="font-display text-xl text-slate-900 dark:text-slate-100">
                    Posts
                  </h3>
                  <p class="mt-1 text-xs uppercase tracking-[0.3em] text-slate-500 dark:text-slate-400">
                    Latest notes
                  </p>
                </div>
              </div>

              <div id="profile-posts" phx-update="stream" class="space-y-4">
                <div
                  id="profile-posts-empty"
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
                  data-role="profile-load-more"
                  phx-click="load_more_posts"
                  phx-disable-with="Loading..."
                  aria-label="Load more posts"
                  variant="secondary"
                >
                  <.icon name="hero-chevron-down" class="size-4" /> Load more
                </.button>
              </div>
            </section>
          </section>
        <% else %>
          <section class="space-y-4">
            <.card class="p-6">
              <p class="text-sm text-slate-600 dark:text-slate-300">
                Profile not found.
              </p>
              <div class="mt-4 flex flex-wrap items-center gap-2">
                <.button navigate={~p"/"} size="sm">Go home</.button>
              </div>
            </.card>
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

  attr :value, :integer, required: true
  attr :label, :string, required: true

  defp stat(assigns) do
    ~H"""
    <div class="rounded-2xl border border-slate-200/80 bg-white/70 px-4 py-3 text-center shadow-sm shadow-slate-200/20 dark:border-slate-700/70 dark:bg-slate-950/50 dark:shadow-slate-900/30">
      <p class="text-lg font-semibold text-slate-900 dark:text-slate-100">{@value}</p>
      <p class="text-[10px] uppercase tracking-[0.25em] text-slate-500 dark:text-slate-400">
        {@label}
      </p>
    </div>
    """
  end

  defp follow_relationship(nil, _profile_user), do: nil
  defp follow_relationship(_current_user, nil), do: nil

  defp follow_relationship(%User{} = current_user, %User{} = profile_user) do
    Relationships.get_by_type_actor_object("Follow", current_user.ap_id, profile_user.ap_id)
  end

  defp count_posts(nil), do: 0
  defp count_posts(%User{} = user), do: Objects.count_notes_by_actor(user.ap_id)

  defp count_followers(nil), do: 0

  defp count_followers(%User{} = user),
    do: Relationships.count_by_type_object("Follow", user.ap_id)

  defp count_following(nil), do: 0

  defp count_following(%User{} = user),
    do: Relationships.count_by_type_actor("Follow", user.ap_id)

  defp posts_cursor([]), do: nil

  defp posts_cursor(posts) when is_list(posts) do
    case List.last(posts) do
      %{id: id} when is_integer(id) -> id
      _ -> nil
    end
  end

  defp post_dom_id(%{object: %{id: id}}) when is_integer(id), do: "post-#{id}"
  defp post_dom_id(_post), do: Ecto.UUID.generate()

  defp refresh_post(socket, post_id) when is_integer(post_id) do
    current_user = socket.assigns.current_user

    case Objects.get(post_id) do
      %{type: "Note"} = object ->
        stream_insert(socket, :posts, StatusVM.decorate(object, current_user))

      _ ->
        socket
    end
  end

  defp notifications_count(nil), do: 0

  defp notifications_count(%User{} = user) do
    user
    |> Notifications.list_for_user(limit: @page_size)
    |> length()
  end
end
