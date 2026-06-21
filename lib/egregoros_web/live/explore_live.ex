defmodule EgregorosWeb.ExploreLive do
  use EgregorosWeb, :live_view

  import Ecto.Query

  alias Egregoros.Activities.Follow
  alias Egregoros.Notifications
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Relationship
  alias Egregoros.Relationships
  alias Egregoros.Repo
  alias Egregoros.User
  alias Egregoros.Users
  alias EgregorosWeb.ProfilePaths
  alias EgregorosWeb.URL
  alias EgregorosWeb.ViewModels.Actor, as: ActorVM
  alias EgregorosWeb.ViewModels.Status, as: StatusVM

  @page_size 12
  @tag_sample_size 200
  @system_nicknames ["internal.fetch", "instance.actor"]
  @follow_graph_relationship_types ["Follow", "GraphFollow"]
  @suggestion_exclusion_relationship_types ["Follow", "FollowRequest", "Block", "Mute"]

  @impl true
  def mount(_params, session, socket) do
    current_user =
      case Map.get(session, "user_id") do
        nil -> nil
        id -> Users.get(id)
      end

    objects = Objects.list_public_notes(limit: @page_size)

    trending_tags = trending_tags(12)

    directory_accounts = directory_accounts(current_user, 12)

    suggestions =
      case current_user do
        %User{} = user -> suggestions(user, 8)
        _ -> []
      end

    followed_tags =
      case current_user do
        %User{ap_id: ap_id} when is_binary(ap_id) ->
          followed_tags(ap_id, 12)

        _ ->
          []
      end

    {:ok,
     assign(socket,
       current_user: current_user,
       notifications_count: notifications_count(current_user),
       trending_tags: trending_tags,
       posts: StatusVM.decorate_many(objects, current_user),
       directory_accounts: directory_accounts,
       suggestions: suggestions,
       followed_tags: followed_tags
     )}
  end

  @impl true
  def handle_event("follow_suggestion", %{"ap_id" => ap_id}, socket) do
    with %User{} = viewer <- socket.assigns.current_user,
         ap_id when is_binary(ap_id) <- to_string(ap_id),
         %User{} = target <- Users.get_by_ap_id(ap_id),
         true <- viewer.ap_id != target.ap_id,
         nil <- Relationships.get_by_type_actor_object("Follow", viewer.ap_id, target.ap_id),
         {:ok, _follow} <- Pipeline.ingest(Follow.build(viewer, target), local: true) do
      suggestions = suggestions(viewer, 8)

      {:noreply,
       socket
       |> put_flash(:info, "Following #{ActorVM.handle(target, target.ap_id)}.")
       |> assign(suggestions: suggestions)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to follow people.")}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <AppShell.app_shell
        id="explore-shell"
        nav_id="explore-nav"
        main_id="explore-main"
        active={:explore}
        current_user={@current_user}
        notifications_count={@notifications_count}
      >
        <section class="space-y-6">
          <.card class="p-6">
            <p class="text-xs font-bold uppercase tracking-wide text-[color:var(--text-muted)]">
              Explore
            </p>
            <h2 class="mt-2 text-2xl font-bold text-[color:var(--text-primary)]">
              Discover what’s happening
            </h2>
            <p class="mt-2 text-sm text-[color:var(--text-secondary)]">
              Trending tags, recent posts, and accounts worth following.
            </p>
          </.card>

          <section :if={@followed_tags != []} data-role="explore-followed-tags" class="space-y-3">
            <.card class="p-6">
              <p class="text-xs font-bold uppercase tracking-wide text-[color:var(--text-muted)]">
                Your tags
              </p>
              <h3 class="mt-2 text-xl font-bold text-[color:var(--text-primary)]">
                Followed hashtags
              </h3>
            </.card>

            <.card class="p-5">
              <div class="flex flex-wrap gap-2">
                <.link
                  :for={tag <- @followed_tags}
                  navigate={~p"/tags/#{tag}"}
                  data-role="explore-followed-tag"
                  class="inline-flex items-center gap-2 border border-[color:var(--border-default)] bg-[color:var(--bg-subtle)] px-3 py-2 text-sm font-semibold text-[color:var(--text-primary)] transition hover:bg-[color:var(--bg-base)]"
                >
                  <.icon name="hero-hashtag" class="size-4 text-[color:var(--text-muted)]" />
                  <span>#{tag}</span>
                </.link>
              </div>
            </.card>
          </section>

          <section :if={@current_user != nil} data-role="explore-suggestions" class="space-y-3">
            <.card class="p-6">
              <p class="text-xs font-bold uppercase tracking-wide text-[color:var(--text-muted)]">
                Suggestions
              </p>
              <h3 class="mt-2 text-xl font-bold text-[color:var(--text-primary)]">
                Accounts to follow
              </h3>
            </.card>

            <.card :if={@suggestions == []} class="p-6">
              <p class="text-sm text-[color:var(--text-secondary)]">
                No suggestions yet. Follow a few accounts to improve recommendations.
              </p>
            </.card>

            <.card :for={user <- @suggestions} class="p-5">
              <div class="flex items-center justify-between gap-4">
                <.link
                  navigate={ProfilePaths.profile_path(user)}
                  class="flex min-w-0 flex-1 items-center gap-4 focus-visible:outline-none focus-brutal"
                >
                  <.avatar
                    name={user.name || user.nickname || user.ap_id}
                    src={URL.absolute(user.avatar_url, user.ap_id)}
                    size="lg"
                  />

                  <div class="min-w-0 flex-1">
                    <p class="truncate text-sm font-bold text-[color:var(--text-primary)]">
                      {user.name || user.nickname || user.ap_id}
                    </p>
                    <p
                      data-role="explore-suggestion-handle"
                      class="truncate font-mono text-xs text-[color:var(--text-muted)]"
                    >
                      {ActorVM.handle(user, user.ap_id)}
                    </p>
                  </div>
                </.link>

                <.button
                  :if={show_follow_button?(@current_user, user)}
                  data-role="explore-suggestion-follow"
                  phx-click="follow_suggestion"
                  phx-value-ap_id={user.ap_id}
                  phx-disable-with="..."
                  size="sm"
                >
                  Follow
                </.button>
              </div>
            </.card>
          </section>

          <section data-role="explore-trending-tags" class="space-y-3">
            <.card class="p-6">
              <p class="text-xs font-bold uppercase tracking-wide text-[color:var(--text-muted)]">
                Trending
              </p>
              <h3 class="mt-2 text-xl font-bold text-[color:var(--text-primary)]">
                Tags people are using
              </h3>
            </.card>

            <.card :if={@trending_tags == []} class="p-6">
              <p class="text-sm text-[color:var(--text-secondary)]">
                No tags yet — post something with a hashtag to get things going.
              </p>
            </.card>

            <.card :if={@trending_tags != []} class="p-5">
              <div class="flex flex-wrap gap-2">
                <.link
                  :for={tag <- @trending_tags}
                  navigate={~p"/tags/#{tag}"}
                  data-role="explore-trending-tag"
                  class="inline-flex items-center gap-2 border border-[color:var(--border-default)] bg-[color:var(--bg-subtle)] px-3 py-2 text-sm font-semibold text-[color:var(--text-primary)] transition hover:bg-[color:var(--bg-base)]"
                >
                  <.icon name="hero-hashtag" class="size-4 text-[color:var(--text-muted)]" />
                  <span>#{tag}</span>
                </.link>
              </div>
            </.card>
          </section>

          <section data-role="explore-trending-statuses" class="space-y-3">
            <.card class="p-6">
              <p class="text-xs font-bold uppercase tracking-wide text-[color:var(--text-muted)]">
                Recent
              </p>
              <h3 class="mt-2 text-xl font-bold text-[color:var(--text-primary)]">
                Latest public posts
              </h3>
            </.card>

            <StatusCard.status_card
              :for={entry <- @posts}
              id={"explore-post-#{entry.object.id}"}
              entry={entry}
              current_user={@current_user}
              reply_mode={if @current_user, do: :modal, else: :navigate}
            />
          </section>

          <section data-role="explore-directory" class="space-y-3">
            <.card class="p-6">
              <p class="text-xs font-bold uppercase tracking-wide text-[color:var(--text-muted)]">
                Directory
              </p>
              <h3 class="mt-2 text-xl font-bold text-[color:var(--text-primary)]">
                Active accounts
              </h3>
            </.card>

            <.card :if={@directory_accounts == []} class="p-6">
              <p class="text-sm text-[color:var(--text-secondary)]">
                No accounts yet.
              </p>
            </.card>

            <.card :for={user <- @directory_accounts} class="p-5">
              <.link
                navigate={ProfilePaths.profile_path(user)}
                class="flex items-center gap-4 focus-visible:outline-none focus-brutal"
              >
                <.avatar
                  name={user.name || user.nickname || user.ap_id}
                  src={URL.absolute(user.avatar_url, user.ap_id)}
                  size="lg"
                />

                <div class="min-w-0 flex-1">
                  <p class="truncate text-sm font-bold text-[color:var(--text-primary)]">
                    {user.name || user.nickname || user.ap_id}
                  </p>
                  <p class="truncate font-mono text-xs text-[color:var(--text-muted)]">
                    {ActorVM.handle(user, user.ap_id)}
                  </p>
                </div>
              </.link>
            </.card>
          </section>
        </section>
      </AppShell.app_shell>
    </Layouts.app>
    """
  end

  defp show_follow_button?(%User{} = current_user, %User{ap_id: ap_id})
       when is_binary(ap_id) and ap_id != "" do
    current_user.ap_id != ap_id
  end

  defp show_follow_button?(_current_user, _user), do: false

  defp notifications_count(nil), do: 0

  defp notifications_count(%User{} = user) do
    user
    |> Notifications.list_for_user(limit: 20, include_offers?: true)
    |> length()
  end

  defp followed_tags(actor_ap_id, limit) when is_binary(actor_ap_id) and is_integer(limit) do
    Relationships.list_by_type_actor("FollowTag", actor_ap_id, limit: limit)
    |> Enum.map(&normalize_hashtag(&1.object))
    |> uniq()
    |> Enum.filter(&valid_hashtag?/1)
    |> Enum.take(limit)
  end

  defp followed_tags(_actor_ap_id, _limit), do: []

  defp suggestions(%User{ap_id: actor_ap_id}, limit)
       when is_binary(actor_ap_id) and actor_ap_id != "" and is_integer(limit) do
    followed_subquery =
      from(r in Relationship,
        where: r.type == "Follow" and r.actor == ^actor_ap_id,
        distinct: r.object,
        select: r.object
      )

    candidate_counts =
      from(r in Relationship,
        where:
          r.type in ^@follow_graph_relationship_types and r.actor in subquery(followed_subquery),
        group_by: r.object,
        select: %{ap_id: r.object, mutuals: count(r.id)}
      )

    candidates =
      from(u in User,
        join: c in subquery(candidate_counts),
        on: c.ap_id == u.ap_id,
        left_join: ex in Relationship,
        on:
          ex.actor == ^actor_ap_id and ex.object == u.ap_id and
            ex.type in ^@suggestion_exclusion_relationship_types,
        where: is_nil(ex.id),
        where: u.ap_id != ^actor_ap_id,
        where: u.nickname not in ^@system_nicknames,
        order_by: [desc: c.mutuals, desc_nulls_last: u.last_activity_at, asc: u.nickname],
        limit: ^limit
      )
      |> Repo.all()

    if length(candidates) < limit do
      needed = limit - length(candidates)
      exclude_ap_ids = [actor_ap_id | Enum.map(candidates, & &1.ap_id)]

      fallback =
        from(u in User,
          left_join: ex in Relationship,
          on:
            ex.actor == ^actor_ap_id and ex.object == u.ap_id and
              ex.type in ^@suggestion_exclusion_relationship_types,
          where: is_nil(ex.id),
          where: u.local == true,
          where: u.ap_id != ^actor_ap_id,
          where: u.ap_id not in ^exclude_ap_ids,
          where: u.nickname not in ^@system_nicknames,
          order_by: [desc_nulls_last: u.last_activity_at, desc: u.inserted_at, asc: u.nickname],
          limit: ^needed
        )
        |> Repo.all()

      candidates ++ fallback
    else
      candidates
    end
  end

  defp suggestions(_actor, _limit), do: []

  defp directory_accounts(current_user, limit) when is_integer(limit) do
    current_user_id =
      case current_user do
        %User{id: id} when is_binary(id) -> id
        _ -> nil
      end

    from(u in User,
      where: u.nickname not in ^@system_nicknames,
      where: u.local == true,
      order_by: [desc_nulls_last: u.last_activity_at, desc: u.inserted_at, desc: u.id],
      limit: ^limit
    )
    |> maybe_where_not_id(current_user_id)
    |> Repo.all()
  end

  defp directory_accounts(_current_user, _limit), do: []

  defp maybe_where_not_id(query, id) when is_binary(id), do: from(u in query, where: u.id != ^id)
  defp maybe_where_not_id(query, _id), do: query

  defp trending_tags(limit) when is_integer(limit) do
    Objects.list_public_notes(limit: @tag_sample_size)
    |> Enum.reduce(%{}, &count_hashtags/2)
    |> Enum.sort_by(fn {_name, info} -> {-info.uses, -MapSet.size(info.accounts)} end)
    |> Enum.map(fn {name, _} -> name end)
    |> Enum.take(limit)
  end

  defp trending_tags(_limit), do: []

  defp count_hashtags(object, acc) do
    actor = Map.get(object, :actor)

    hashtags = hashtags_from_activity_tags(object)

    Enum.reduce(hashtags, acc, fn hashtag, counts ->
      Map.update(
        counts,
        hashtag,
        %{uses: 1, accounts: MapSet.new(List.wrap(actor))},
        fn existing ->
          %{
            uses: existing.uses + 1,
            accounts: MapSet.union(existing.accounts, MapSet.new(List.wrap(actor)))
          }
        end
      )
    end)
  end

  defp hashtags_from_activity_tags(%{data: %{} = data}) do
    data
    |> Map.get("tag", [])
    |> List.wrap()
    |> Enum.filter(&is_map/1)
    |> Enum.filter(&(Map.get(&1, "type") == "Hashtag"))
    |> Enum.map(&Map.get(&1, "name"))
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&normalize_hashtag/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp hashtags_from_activity_tags(_object), do: []

  defp normalize_hashtag(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.trim_leading("#")
    |> String.downcase()
  end

  defp normalize_hashtag(_name), do: ""

  defp valid_hashtag?(tag) when is_binary(tag) do
    Regex.match?(~r/^[\p{L}\p{N}_][\p{L}\p{N}_-]{0,63}$/u, tag)
  end

  defp valid_hashtag?(_tag), do: false

  defp uniq(entries) when is_list(entries) do
    {list, _seen} =
      Enum.reduce(entries, {[], MapSet.new()}, fn entry, {acc, seen} ->
        if MapSet.member?(seen, entry) do
          {acc, seen}
        else
          {[entry | acc], MapSet.put(seen, entry)}
        end
      end)

    Enum.reverse(list)
  end

  defp uniq(_entries), do: []
end
