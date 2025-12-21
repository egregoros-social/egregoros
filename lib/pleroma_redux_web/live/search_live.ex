defmodule PleromaReduxWeb.SearchLive do
  use PleromaReduxWeb, :live_view

  alias PleromaRedux.Notifications
  alias PleromaRedux.User
  alias PleromaRedux.Users
  alias PleromaReduxWeb.ProfilePaths
  alias PleromaReduxWeb.URL
  alias PleromaReduxWeb.ViewModels.Actor, as: ActorVM

  @page_size 20

  @impl true
  def mount(params, session, socket) do
    current_user =
      case Map.get(session, "user_id") do
        nil -> nil
        id -> Users.get(id)
      end

    socket =
      socket
      |> assign(
        current_user: current_user,
        notifications_count: notifications_count(current_user)
      )
      |> apply_params(params)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_params(socket, params)}
  end

  @impl true
  def handle_event("search", %{"search" => %{"q" => q}}, socket) do
    q = q |> to_string() |> String.trim()

    {:noreply,
     if q == "" do
       push_patch(socket, to: ~p"/search")
     else
       push_patch(socket, to: ~p"/search?#{%{q: q}}")
     end}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <AppShell.app_shell
        id="search-shell"
        nav_id="search-nav"
        main_id="search-main"
        active={:search}
        current_user={@current_user}
        notifications_count={@notifications_count}
      >
        <section class="space-y-4">
          <.card class="p-6">
            <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <p class="text-xs uppercase tracking-[0.3em] text-slate-500 dark:text-slate-400">
                  Search
                </p>
                <h2 class="mt-2 font-display text-2xl text-slate-900 dark:text-slate-100">
                  Find people
                </h2>
              </div>

              <.form
                for={@search_form}
                id="search-form"
                phx-change="search"
                phx-submit="search"
                class="flex w-full flex-col gap-3 sm:w-auto sm:flex-row sm:items-end"
              >
                <div class="flex-1">
                  <.input
                    type="text"
                    field={@search_form[:q]}
                    label="Query"
                    placeholder="Search by name or handle"
                    phx-debounce="300"
                  />
                </div>
                <.button type="submit" variant="secondary" class="sm:mb-0.5">Search</.button>
              </.form>
            </div>
          </.card>

          <div data-role="search-results" class="space-y-3">
            <.card :if={@query != "" and @results == []} class="p-6">
              <p class="text-sm text-slate-600 dark:text-slate-300">
                No matching accounts found.
              </p>
            </.card>

            <.card :if={@query == ""} class="p-6">
              <p class="text-sm text-slate-600 dark:text-slate-300">
                Type a query to search for accounts.
              </p>
            </.card>

            <.card :for={user <- @results} class="p-5">
              <.link
                navigate={ProfilePaths.profile_path(user)}
                class="flex items-center gap-4 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400"
              >
                <.avatar
                  name={user.name || user.nickname || user.ap_id}
                  src={URL.absolute(user.avatar_url, user.ap_id)}
                  size="lg"
                />

                <div class="min-w-0 flex-1">
                  <p class="truncate text-sm font-semibold text-slate-900 dark:text-slate-100">
                    {user.name || user.nickname || user.ap_id}
                  </p>
                  <p
                    data-role="search-result-handle"
                    class="truncate text-xs text-slate-500 dark:text-slate-400"
                  >
                    {ActorVM.handle(user, user.ap_id)}
                  </p>
                </div>
              </.link>
            </.card>
          </div>
        </section>
      </AppShell.app_shell>
    </Layouts.app>
    """
  end

  defp apply_params(socket, %{} = params) do
    q = params |> Map.get("q", "") |> to_string() |> String.trim()

    results =
      if q == "" do
        []
      else
        Users.search(q, limit: @page_size)
      end

    assign(socket,
      query: q,
      results: results,
      search_form: Phoenix.Component.to_form(%{"q" => q}, as: :search)
    )
  end

  defp notifications_count(nil), do: 0

  defp notifications_count(%User{} = user) do
    user
    |> Notifications.list_for_user(limit: 20)
    |> length()
  end
end
