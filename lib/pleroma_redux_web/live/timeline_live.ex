defmodule PleromaReduxWeb.TimelineLive do
  use PleromaReduxWeb, :live_view

  alias PleromaRedux.Activities.Announce
  alias PleromaRedux.Activities.EmojiReact
  alias PleromaRedux.Activities.Like
  alias PleromaRedux.Activities.Undo
  alias PleromaRedux.Federation
  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Publish
  alias PleromaRedux.Relationships
  alias PleromaRedux.Timeline
  alias PleromaRedux.User
  alias PleromaRedux.Users
  alias PleromaReduxWeb.URL

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

    form = Phoenix.Component.to_form(%{"content" => ""}, as: :post)
    follow_form = Phoenix.Component.to_form(%{"handle" => ""}, as: :follow)

    {:ok,
     assign(socket,
       timeline: timeline,
       home_actor_ids: home_actor_ids(current_user),
       posts: decorate_posts(list_timeline_posts(timeline, current_user), current_user),
       error: nil,
       follow_error: nil,
       follow_success: nil,
       following: list_following(current_user),
       form: form,
       follow_form: follow_form,
       current_user: current_user
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    timeline = timeline_from_params(params, socket.assigns.current_user)

    socket =
      if timeline == socket.assigns.timeline do
        socket
      else
        assign(socket,
          timeline: timeline,
          posts:
            decorate_posts(
              list_timeline_posts(timeline, socket.assigns.current_user),
              socket.assigns.current_user
            )
        )
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("create_post", %{"post" => %{"content" => content}}, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, assign(socket, error: "Register to post.")}

      user ->
        case Publish.post_note(user, content) do
          {:ok, _post} ->
            {:noreply,
             assign(socket,
               form: Phoenix.Component.to_form(%{"content" => ""}, as: :post),
               error: nil
             )}

          {:error, :empty} ->
            {:noreply,
             assign(socket,
               error: "Post can't be empty.",
               form: Phoenix.Component.to_form(%{"content" => content}, as: :post)
             )}
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
            posts = maybe_refresh_home_posts(socket, user)

            {:noreply,
             assign(socket,
               follow_form: Phoenix.Component.to_form(%{"handle" => ""}, as: :follow),
               follow_error: nil,
               follow_success: "Following #{remote.ap_id}.",
               following: list_following(user),
               home_actor_ids: home_actor_ids,
               posts: posts
             )}

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
      posts = maybe_refresh_home_posts(socket, user)

      {:noreply,
       assign(socket,
         following: list_following(user),
         home_actor_ids: home_actor_ids,
         posts: posts
       )}
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
         %{object: post, liked?: liked?} <-
           Enum.find(socket.assigns.posts, &(&1.object.id == post_id)) do
      if liked? do
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
         %{object: post, reposted?: reposted?} <-
           Enum.find(socket.assigns.posts, &(&1.object.id == post_id)) do
      if reposted? do
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
         %{object: post} <- Enum.find(socket.assigns.posts, &(&1.object.id == post_id)) do
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

  @impl true
  def handle_info({:post_created, post}, socket) do
    if include_post?(post, socket.assigns.timeline, socket.assigns.home_actor_ids) do
      {:noreply,
       update(socket, :posts, fn posts ->
         [decorate_post(post, socket.assigns.current_user) | posts]
       end)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <section id="timeline-shell" class="grid gap-6 lg:grid-cols-12 lg:items-start">
        <aside id="timeline-sidebar" class="space-y-6 lg:col-span-4">
          <div class="rounded-3xl border border-white/80 bg-white/80 p-6 shadow-xl shadow-slate-200/40 backdrop-blur dark:border-slate-700/60 dark:bg-slate-900/70 dark:shadow-slate-900/40 animate-rise">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-xs uppercase tracking-[0.3em] text-slate-500 dark:text-slate-400">
                  Compose
                </p>
                <h2 class="mt-2 font-display text-xl text-slate-900 dark:text-slate-100">
                  Broadcast a short note
                </h2>
              </div>
              <div class="hidden text-right text-xs text-slate-500 dark:text-slate-400 sm:block">
                Live timeline updates
              </div>
            </div>

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
                  label="Follow"
                  placeholder="bob@remote.example"
                  class="w-full rounded-2xl border border-slate-200/80 bg-white/70 px-4 py-3 text-sm text-slate-900 outline-none transition focus:border-slate-400 focus:ring-2 focus:ring-slate-200 dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-100 dark:focus:border-slate-400 dark:focus:ring-slate-600"
                />
              </div>

              <button
                type="submit"
                class="rounded-full border border-slate-200/80 bg-white/70 px-5 py-3 text-sm font-semibold text-slate-700 transition hover:-translate-y-0.5 hover:bg-white dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:hover:bg-slate-950"
              >
                Follow
              </button>
            </.form>

            <p :if={@follow_error} class="mt-3 text-sm text-rose-500">{@follow_error}</p>
            <p :if={@follow_success} class="mt-3 text-sm text-emerald-600 dark:text-emerald-400">
              {@follow_success}
            </p>

            <div
              :if={@current_user}
              class="mt-8 border-t border-slate-200/70 pt-6 dark:border-slate-700/60"
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
                            do: user_handle(entry.target, entry.target.ap_id),
                            else: entry.relationship.object}
                        </p>
                      </div>
                    </div>

                    <button
                      type="button"
                      data-role="unfollow"
                      phx-click="unfollow"
                      phx-value-id={entry.relationship.id}
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
            </div>

            <.form for={@form} id="timeline-form" phx-submit="create_post" class="mt-6 space-y-4">
              <.input
                type="textarea"
                field={@form[:content]}
                placeholder="What's happening?"
                rows="3"
                phx-debounce="blur"
                class="w-full resize-none rounded-2xl border border-slate-200/80 bg-white/70 px-4 py-3 text-sm text-slate-900 outline-none transition focus:border-slate-400 focus:ring-2 focus:ring-slate-200 dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-100 dark:focus:border-slate-400 dark:focus:ring-slate-600"
              />

              <div class="flex flex-wrap items-center justify-between gap-3">
                <p :if={@error} class="text-sm text-rose-500">{@error}</p>
                <div class="ml-auto flex items-center gap-3">
                  <span class="text-xs uppercase tracking-[0.25em] text-slate-400 dark:text-slate-500">
                    {if @current_user, do: @current_user.nickname, else: "guest"}
                  </span>
                  <button
                    type="submit"
                    class="rounded-full bg-slate-900 px-5 py-2 text-sm font-semibold text-white shadow-lg shadow-slate-900/20 transition hover:-translate-y-0.5 hover:bg-slate-800 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-white"
                  >
                    Post
                  </button>
                </div>
              </div>
            </.form>
          </div>
        </aside>

        <section id="timeline-feed" class="space-y-4 lg:col-span-8">
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

          <%= for {entry, idx} <- Enum.with_index(@posts) do %>
            <article
              id={"post-#{entry.object.id}"}
              class="rounded-3xl border border-white/80 bg-white/80 p-6 shadow-lg shadow-slate-200/30 backdrop-blur transition hover:-translate-y-0.5 hover:shadow-xl dark:border-slate-700/60 dark:bg-slate-900/70 dark:shadow-slate-900/50 animate-rise"
              style={"animation-delay: #{idx * 45}ms"}
            >
              <div class="flex items-start gap-4">
                <div class="shrink-0">
                  <%= if is_binary(entry.actor.avatar_url) and entry.actor.avatar_url != "" do %>
                    <img
                      src={entry.actor.avatar_url}
                      alt={entry.actor.display_name}
                      class="h-12 w-12 rounded-2xl border border-slate-200/80 bg-white object-cover shadow-sm shadow-slate-200/40 dark:border-slate-700/60 dark:bg-slate-950/60 dark:shadow-slate-900/40"
                      loading="lazy"
                    />
                  <% else %>
                    <div class="flex h-12 w-12 items-center justify-center rounded-2xl border border-slate-200/80 bg-white/70 text-sm font-semibold text-slate-700 shadow-sm shadow-slate-200/30 dark:border-slate-700/60 dark:bg-slate-950/60 dark:text-slate-200 dark:shadow-slate-900/40">
                      {avatar_initial(entry.actor.display_name)}
                    </div>
                  <% end %>
                </div>

                <div class="min-w-0 flex-1">
                  <div class="flex items-start justify-between gap-3">
                    <div class="min-w-0">
                      <p
                        data-role="post-actor-name"
                        class="truncate text-sm font-semibold text-slate-900 dark:text-slate-100"
                      >
                        {entry.actor.display_name}
                      </p>
                      <div class="mt-1 flex flex-wrap items-center gap-2">
                        <span
                          data-role="post-actor-handle"
                          class="truncate text-xs text-slate-500 dark:text-slate-400"
                        >
                          {entry.actor.handle}
                        </span>

                        <span class="text-[10px] uppercase tracking-[0.25em] text-slate-400 dark:text-slate-500">
                          {if entry.object.local, do: "local", else: "remote"}
                        </span>
                      </div>
                    </div>

                    <span class="text-xs text-slate-400 dark:text-slate-500">
                      {format_time(entry.object.inserted_at)}
                    </span>
                  </div>

                  <p class="mt-3 text-base leading-relaxed text-slate-900 dark:text-slate-100">
                    {entry.object.data["content"]}
                  </p>
                </div>
              </div>

              <div class="mt-5 flex flex-wrap items-center gap-3">
                <button
                  :if={@current_user}
                  type="button"
                  data-role="like"
                  phx-click="toggle_like"
                  phx-value-id={entry.object.id}
                  class="inline-flex items-center gap-2 rounded-full border border-slate-200/80 bg-white/70 px-4 py-2 text-sm font-semibold text-slate-700 transition hover:-translate-y-0.5 hover:bg-white dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:hover:bg-slate-950"
                >
                  {if entry.liked?, do: "Unlike", else: "Like"}
                  <span class="text-xs font-normal text-slate-500 dark:text-slate-400">
                    {entry.likes_count}
                  </span>
                </button>

                <button
                  :if={@current_user}
                  type="button"
                  data-role="repost"
                  phx-click="toggle_repost"
                  phx-value-id={entry.object.id}
                  class="inline-flex items-center gap-2 rounded-full border border-slate-200/80 bg-white/70 px-4 py-2 text-sm font-semibold text-slate-700 transition hover:-translate-y-0.5 hover:bg-white dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:hover:bg-slate-950"
                >
                  {if entry.reposted?, do: "Unrepost", else: "Repost"}
                  <span class="text-xs font-normal text-slate-500 dark:text-slate-400">
                    {entry.reposts_count}
                  </span>
                </button>

                <div :if={@current_user} class="flex flex-wrap items-center gap-2">
                  <%= for emoji <- reaction_emojis() do %>
                    <% reaction = Map.get(entry.reactions, emoji, %{count: 0, reacted?: false}) %>

                    <button
                      type="button"
                      data-role="reaction"
                      data-emoji={emoji}
                      phx-click="toggle_reaction"
                      phx-value-id={entry.object.id}
                      phx-value-emoji={emoji}
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
          <% end %>
        </section>
      </section>
    </Layouts.app>
    """
  end

  defp decorate_posts(posts, current_user) when is_list(posts) do
    Enum.map(posts, &decorate_post(&1, current_user))
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

  defp list_timeline_posts(:home, %User{} = user) do
    Objects.list_home_notes(user.ap_id)
  end

  defp list_timeline_posts(_timeline, _user) do
    Objects.list_notes()
  end

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

  defp maybe_refresh_home_posts(%{assigns: %{timeline: :home}}, %User{} = user) do
    decorate_posts(list_timeline_posts(:home, user), user)
  end

  defp maybe_refresh_home_posts(socket, _user), do: socket.assigns.posts

  defp decorate_post(post, current_user) do
    %{
      object: post,
      actor: actor_card(post.actor),
      likes_count: Relationships.count_by_type_object("Like", post.ap_id),
      liked?: liked_by_current_user?(post, current_user),
      reposts_count: Relationships.count_by_type_object("Announce", post.ap_id),
      reposted?: reposted_by_current_user?(post, current_user),
      reactions: reactions_for_post(post, current_user)
    }
  end

  defp actor_card(nil) do
    %{
      ap_id: nil,
      display_name: "Unknown",
      handle: "@unknown",
      avatar_url: nil,
      local?: false
    }
  end

  defp actor_card(ap_id) when is_binary(ap_id) do
    case Users.get_by_ap_id(ap_id) do
      %User{} = user ->
        %{
          ap_id: user.ap_id,
          display_name: user.name || user.nickname || ap_id,
          handle: user_handle(user, ap_id),
          avatar_url: URL.absolute(user.avatar_url),
          local?: user.local
        }

      nil ->
        %{
          ap_id: ap_id,
          display_name: ap_id,
          handle: ap_id,
          avatar_url: nil,
          local?: false
        }
    end
  end

  defp user_handle(%User{nickname: nickname, local: true}, _ap_id) when is_binary(nickname) do
    "@" <> nickname
  end

  defp user_handle(%User{nickname: nickname}, ap_id)
       when is_binary(nickname) and is_binary(ap_id) do
    case URI.parse(ap_id) do
      %{host: host} when is_binary(host) and host != "" -> "#{nickname}@#{host}"
      _ -> nickname
    end
  end

  defp liked_by_current_user?(_post, nil), do: false

  defp liked_by_current_user?(post, %User{} = current_user) do
    Relationships.get_by_type_actor_object("Like", current_user.ap_id, post.ap_id) != nil
  end

  defp reposted_by_current_user?(_post, nil), do: false

  defp reposted_by_current_user?(post, %User{} = current_user) do
    Relationships.get_by_type_actor_object("Announce", current_user.ap_id, post.ap_id) != nil
  end

  defp reactions_for_post(post, current_user) do
    for emoji <- reaction_emojis(), into: %{} do
      relationship_type = "EmojiReact:" <> emoji

      {emoji,
       %{
         count: Relationships.count_by_type_object(relationship_type, post.ap_id),
         reacted?: reacted_by_current_user?(post, current_user, relationship_type)
       }}
    end
  end

  defp reacted_by_current_user?(_post, nil, _relationship_type), do: false

  defp reacted_by_current_user?(post, %User{} = current_user, relationship_type)
       when is_binary(relationship_type) do
    Relationships.get_by_type_actor_object(relationship_type, current_user.ap_id, post.ap_id) !=
      nil
  end

  defp reaction_emojis do
    ["🔥", "👍", "❤️"]
  end

  defp refresh_post(socket, post_id) when is_integer(post_id) do
    current_user = socket.assigns.current_user

    update(socket, :posts, fn posts ->
      Enum.map(posts, fn
        %{object: %{id: ^post_id} = object} -> decorate_post(object, current_user)
        entry -> entry
      end)
    end)
  end

  defp format_time(%DateTime{} = dt) do
    dt
    |> DateTime.to_naive()
    |> NaiveDateTime.truncate(:second)
    |> NaiveDateTime.to_string()
  end

  defp format_time(%NaiveDateTime{} = dt) do
    dt
    |> NaiveDateTime.truncate(:second)
    |> NaiveDateTime.to_string()
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
