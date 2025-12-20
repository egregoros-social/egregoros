defmodule PleromaReduxWeb.StatusLive do
  use PleromaReduxWeb, :live_view

  alias PleromaRedux.Notifications
  alias PleromaRedux.Objects
  alias PleromaRedux.User
  alias PleromaRedux.Users
  alias PleromaReduxWeb.Endpoint
  alias PleromaReduxWeb.ViewModels.Status, as: StatusVM

  @impl true
  def mount(%{"nickname" => nickname, "uuid" => uuid}, session, socket) do
    current_user =
      case Map.get(session, "user_id") do
        nil -> nil
        id -> Users.get(id)
      end

    object = object_for_uuid(uuid)

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
        nickname: nickname,
        uuid: uuid,
        status: status_entry,
        ancestors: ancestor_entries,
        descendants: descendant_entries
      )

    {:ok, socket}
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

  defp timeline_href(%{id: _}), do: ~p"/?timeline=home"
  defp timeline_href(_user), do: ~p"/?timeline=public"
end

