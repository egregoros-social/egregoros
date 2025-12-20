defmodule PleromaReduxWeb.TagLive do
  use PleromaReduxWeb, :live_view

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

    posts = Objects.list_notes_by_hashtag(tag, limit: @page_size)

    {:ok,
     socket
     |> assign(
       current_user: current_user,
       notifications_count: notifications_count(current_user),
       tag: tag,
       posts: StatusVM.decorate_many(posts, current_user)
     )}
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
        </section>
      </AppShell.app_shell>
    </Layouts.app>
    """
  end

  defp notifications_count(nil), do: 0

  defp notifications_count(%User{} = user) do
    user
    |> Notifications.list_for_user(limit: @page_size)
    |> length()
  end

  defp timeline_href(%{id: _}), do: ~p"/?timeline=home"
  defp timeline_href(_user), do: ~p"/?timeline=public"
end

