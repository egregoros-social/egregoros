defmodule EgregorosWeb.PrivacyLive do
  use EgregorosWeb, :live_view

  alias Egregoros.Notifications
  alias Egregoros.Relationship
  alias Egregoros.Relationships
  alias Egregoros.Repo
  alias Egregoros.User
  alias Egregoros.Users
  alias EgregorosWeb.URL
  alias EgregorosWeb.ViewModels.Actor, as: ActorVM

  @impl true
  def mount(_params, session, socket) do
    current_user =
      case Map.get(session, "user_id") do
        nil -> nil
        id -> Users.get(id)
      end

    mutes = list_relationships("Mute", current_user)
    blocks = list_relationships("Block", current_user)

    {:ok,
     socket
     |> assign(
       current_user: current_user,
       notifications_count: notifications_count(current_user),
       mutes: mutes,
       blocks: blocks,
       targets_by_ap_id: target_cards(mutes ++ blocks)
     )}
  end

  @impl true
  def handle_event("privacy-unmute", %{"id" => id}, socket) do
    {:noreply, delete_relationship(socket, id, "Mute", :mutes)}
  end

  def handle_event("privacy-unblock", %{"id" => id}, socket) do
    {:noreply, delete_relationship(socket, id, "Block", :blocks)}
  end

  defp delete_relationship(socket, id, type, key) do
    with %User{} = current_user <- socket.assigns.current_user,
         {relationship_id, ""} <- Integer.parse(to_string(id)),
         %Relationship{} = relationship <- Relationships.get(relationship_id),
         true <- relationship.type == type,
         true <- relationship.actor == current_user.ap_id,
         {:ok, _relationship} <- Repo.delete(relationship) do
      socket
      |> assign(
        key,
        Enum.reject(Map.get(socket.assigns, key, []), &(&1.id == relationship_id))
      )
      |> refresh_targets()
    else
      _ -> socket
    end
  end

  defp refresh_targets(socket) do
    mutes = Map.get(socket.assigns, :mutes, [])
    blocks = Map.get(socket.assigns, :blocks, [])
    assign(socket, :targets_by_ap_id, target_cards(mutes ++ blocks))
  end

  defp target_cards(relationships) when is_list(relationships) do
    ap_ids =
      relationships
      |> Enum.map(& &1.object)
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    ap_ids
    |> Users.list_by_ap_ids()
    |> Map.new(fn user ->
      {user.ap_id,
       %{
         display_name: user.name || user.nickname || user.ap_id,
         handle: ActorVM.handle(user, user.ap_id),
         avatar_url: URL.absolute(user.avatar_url, user.ap_id),
         emojis: Map.get(user, :emojis, [])
       }}
    end)
  end

  defp target_cards(_relationships), do: %{}

  defp list_relationships(_type, nil), do: []

  defp list_relationships(type, %User{} = user) when is_binary(type) do
    Relationships.list_by_type_actor(type, user.ap_id, limit: 80)
  end

  defp notifications_count(nil), do: 0

  defp notifications_count(%User{} = user) do
    user
    |> Notifications.list_for_user(limit: 20)
    |> length()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <AppShell.app_shell
        id="privacy-shell"
        nav_id="privacy-nav"
        main_id="privacy-main"
        active={:settings}
        current_user={@current_user}
        notifications_count={@notifications_count}
      >
        <section class="space-y-6">
          <.card class="p-6">
            <div class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <p class="text-xs font-semibold uppercase tracking-[0.3em] text-slate-500 dark:text-slate-400">
                  Settings
                </p>
                <h2 class="mt-2 font-display text-2xl text-slate-900 dark:text-slate-100">
                  Privacy
                </h2>
              </div>
              <.button navigate={~p"/settings"} variant="secondary" size="sm">
                <.icon name="hero-chevron-left" class="size-4" /> Back
              </.button>
            </div>
          </.card>

          <%= if @current_user do %>
            <div class="grid gap-6 lg:grid-cols-2">
              <.card class="p-6">
                <div class="flex items-center justify-between gap-4">
                  <h3 class="font-display text-xl text-slate-900 dark:text-slate-100">
                    Muted accounts
                  </h3>
                  <span class="text-sm text-slate-500 dark:text-slate-400">
                    {length(@mutes)}
                  </span>
                </div>

                <div class="mt-4 space-y-3">
                  <p :if={@mutes == []} class="text-sm text-slate-600 dark:text-slate-300">
                    No muted accounts yet.
                  </p>

                  <div
                    :for={mute <- @mutes}
                    id={"mute-#{mute.id}"}
                    class="flex items-center justify-between gap-4 rounded-2xl border border-slate-200/80 bg-white/70 px-4 py-3 text-sm shadow-sm shadow-slate-200/10 dark:border-slate-700/70 dark:bg-slate-950/50 dark:shadow-slate-900/30"
                  >
                    <% target = Map.get(@targets_by_ap_id, mute.object) %>
                    <div class="flex min-w-0 items-center gap-3">
                      <.avatar
                        size="xs"
                        name={Map.get(target || %{}, :display_name, mute.object)}
                        src={Map.get(target || %{}, :avatar_url)}
                      />
                      <div class="min-w-0">
                        <p class="truncate font-semibold text-slate-900 dark:text-white">
                          {emoji_inline(
                            Map.get(target || %{}, :display_name, mute.object),
                            Map.get(target || %{}, :emojis, [])
                          )}
                        </p>
                        <p
                          data-role="privacy-target-handle"
                          class="truncate text-xs text-slate-500 dark:text-slate-400"
                        >
                          {Map.get(target || %{}, :handle, mute.object)}
                        </p>
                      </div>
                    </div>
                    <button
                      type="button"
                      data-role="privacy-unmute"
                      phx-click="privacy-unmute"
                      phx-value-id={mute.id}
                      class="rounded-2xl border border-slate-200 bg-white px-3 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-slate-700 transition hover:-translate-y-0.5 hover:bg-slate-50 hover:shadow-md hover:shadow-slate-200/30 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-100 dark:hover:bg-slate-800 dark:hover:shadow-slate-900/30"
                    >
                      Unmute
                    </button>
                  </div>
                </div>
              </.card>

              <.card class="p-6">
                <div class="flex items-center justify-between gap-4">
                  <h3 class="font-display text-xl text-slate-900 dark:text-slate-100">
                    Blocked accounts
                  </h3>
                  <span class="text-sm text-slate-500 dark:text-slate-400">
                    {length(@blocks)}
                  </span>
                </div>

                <div class="mt-4 space-y-3">
                  <p :if={@blocks == []} class="text-sm text-slate-600 dark:text-slate-300">
                    No blocked accounts yet.
                  </p>

                  <div
                    :for={block <- @blocks}
                    id={"block-#{block.id}"}
                    class="flex items-center justify-between gap-4 rounded-2xl border border-slate-200/80 bg-white/70 px-4 py-3 text-sm shadow-sm shadow-slate-200/10 dark:border-slate-700/70 dark:bg-slate-950/50 dark:shadow-slate-900/30"
                  >
                    <% target = Map.get(@targets_by_ap_id, block.object) %>
                    <div class="flex min-w-0 items-center gap-3">
                      <.avatar
                        size="xs"
                        name={Map.get(target || %{}, :display_name, block.object)}
                        src={Map.get(target || %{}, :avatar_url)}
                      />
                      <div class="min-w-0">
                        <p class="truncate font-semibold text-slate-900 dark:text-white">
                          {emoji_inline(
                            Map.get(target || %{}, :display_name, block.object),
                            Map.get(target || %{}, :emojis, [])
                          )}
                        </p>
                        <p
                          data-role="privacy-target-handle"
                          class="truncate text-xs text-slate-500 dark:text-slate-400"
                        >
                          {Map.get(target || %{}, :handle, block.object)}
                        </p>
                      </div>
                    </div>
                    <button
                      type="button"
                      data-role="privacy-unblock"
                      phx-click="privacy-unblock"
                      phx-value-id={block.id}
                      class="rounded-2xl border border-slate-200 bg-white px-3 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-slate-700 transition hover:-translate-y-0.5 hover:bg-slate-50 hover:shadow-md hover:shadow-slate-200/30 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-100 dark:hover:bg-slate-800 dark:hover:shadow-slate-900/30"
                    >
                      Unblock
                    </button>
                  </div>
                </div>
              </.card>
            </div>
          <% else %>
            <.card class="p-6">
              <p data-role="privacy-auth-required" class="text-sm text-slate-600 dark:text-slate-300">
                Sign in to manage blocks and mutes.
              </p>
              <div class="mt-4 flex flex-wrap items-center gap-2">
                <.button navigate={~p"/login"} size="sm">Login</.button>
                <.button navigate={~p"/register"} size="sm" variant="secondary">Register</.button>
              </div>
            </.card>
          <% end %>
        </section>
      </AppShell.app_shell>
    </Layouts.app>
    """
  end
end
