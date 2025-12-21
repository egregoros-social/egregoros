defmodule PleromaReduxWeb.AppShell do
  use PleromaReduxWeb, :html

  alias PleromaReduxWeb.URL

  attr :id, :string, default: "app-shell"
  attr :nav_id, :string, default: "app-nav"
  attr :main_id, :string, default: "app-main"
  attr :aside_id, :string, default: "app-aside"

  attr :active, :atom,
    values: [:timeline, :search, :notifications, :profile, :settings],
    required: true

  attr :current_user, :any, default: nil
  attr :notifications_count, :integer, default: 0

  slot :nav_top
  slot :nav_bottom
  slot :aside
  slot :inner_block, required: true

  def app_shell(assigns) do
    ~H"""
    <section
      id={@id}
      class="grid gap-6 pb-24 lg:grid-cols-12 lg:items-start lg:pb-0"
      data-role="app-shell"
    >
      <div
        id={@nav_id}
        data-role="app-shell-sidebar"
        class={[
          "contents lg:block lg:space-y-6",
          @aside == [] && "lg:col-span-4",
          @aside != [] && "lg:col-span-3",
          "lg:sticky lg:top-10 lg:max-h-[calc(100vh-5rem)] lg:overflow-y-auto"
        ]}
      >
        {render_slot(@nav_top)}

        <nav class="hidden lg:block" aria-label="Primary navigation">
          <.card class="p-4">
            <%= if @current_user do %>
              <div class="flex items-center gap-3">
                <.avatar
                  size="sm"
                  name={display_name(@current_user)}
                  src={avatar_src(@current_user)}
                />
                <div class="min-w-0">
                  <p class="truncate text-sm font-semibold text-slate-900 dark:text-slate-100">
                    {display_name(@current_user)}
                  </p>
                  <p class="truncate text-xs text-slate-500 dark:text-slate-400">
                    @{to_string(nickname(@current_user))}
                  </p>
                </div>
              </div>
            <% else %>
              <p class="text-xs uppercase tracking-[0.3em] text-slate-500 dark:text-slate-400">
                Guest mode
              </p>
              <p class="mt-2 text-sm text-slate-600 dark:text-slate-300">
                Public feed is available. Sign in for home, posting, and notifications.
              </p>
            <% end %>

            <div class="mt-4 space-y-3">
              <form
                data-role="app-shell-search"
                action={~p"/search"}
                method="get"
                class="rounded-2xl border border-slate-200/80 bg-white/70 px-3 py-2 shadow-sm shadow-slate-200/20 backdrop-blur dark:border-slate-700/70 dark:bg-slate-950/50 dark:shadow-slate-900/40"
              >
                <div class="flex items-center gap-2">
                  <.icon name="hero-magnifying-glass" class="size-4 text-slate-400" />
                  <input
                    type="search"
                    name="q"
                    aria-label="Search"
                    placeholder="Search"
                    class="w-full border-0 bg-transparent p-0 text-sm text-slate-900 outline-none placeholder:text-slate-400 focus:ring-0 dark:text-slate-100 dark:placeholder:text-slate-500"
                  />
                </div>
              </form>

              <div class="space-y-2">
                <.nav_link
                  role="nav-timeline"
                  active={@active == :timeline}
                  icon="hero-home"
                  label="Timeline"
                  navigate={timeline_href(@current_user)}
                />

                <.nav_link
                  role="nav-search"
                  active={@active == :search}
                  icon="hero-magnifying-glass"
                  label="Search"
                  navigate={~p"/search"}
                />

                <%= if @current_user do %>
                  <.nav_link
                    role="nav-notifications"
                    active={@active == :notifications}
                    icon="hero-bell"
                    label="Notifications"
                    navigate={~p"/notifications"}
                  >
                    <span
                      :if={@notifications_count > 0}
                      data-role="nav-notifications-count"
                      class="ml-auto inline-flex items-center rounded-full bg-rose-600 px-2 py-0.5 text-xs font-semibold text-white"
                    >
                      {@notifications_count}
                    </span>
                  </.nav_link>

                  <.nav_link
                    role="nav-profile"
                    active={@active == :profile}
                    icon="hero-user-circle"
                    label="Profile"
                    navigate={profile_href(@current_user)}
                  />

                  <.nav_link
                    role="nav-settings"
                    active={@active == :settings}
                    icon="hero-cog-6-tooth"
                    label="Settings"
                    navigate={~p"/settings"}
                  />
                <% else %>
                  <.nav_link
                    role="nav-login"
                    active={false}
                    icon="hero-arrow-right-on-rectangle"
                    label="Login"
                    navigate={~p"/login"}
                  />

                  <.nav_link
                    role="nav-register"
                    active={false}
                    icon="hero-user-plus"
                    label="Register"
                    navigate={~p"/register"}
                  />
                <% end %>
              </div>
            </div>
          </.card>
        </nav>

        {render_slot(@nav_bottom)}
      </div>

      <main
        id={@main_id}
        class={[
          @aside == [] && "lg:col-span-8",
          @aside != [] && "lg:col-span-6"
        ]}
      >
        {render_slot(@inner_block)}
      </main>

      <aside
        :if={@aside != []}
        id={@aside_id}
        class="space-y-6 lg:col-span-3 lg:sticky lg:top-10"
      >
        {render_slot(@aside)}
      </aside>

      <nav
        class="fixed inset-x-4 bottom-4 z-40 rounded-3xl border border-white/70 bg-white/90 px-2 py-2 shadow-xl shadow-slate-900/10 backdrop-blur dark:border-slate-700/70 dark:bg-slate-950/70 dark:shadow-slate-900/40 lg:hidden"
        data-role="bottom-nav"
        aria-label="Primary navigation"
      >
        <div class="flex items-center justify-between gap-2">
          <.bottom_nav_link
            role="nav-timeline"
            active={@active == :timeline}
            icon="hero-home"
            label="Timeline"
            navigate={timeline_href(@current_user)}
          />

          <.bottom_nav_link
            role="nav-search"
            active={@active == :search}
            icon="hero-magnifying-glass"
            label="Search"
            navigate={~p"/search"}
          />

          <%= if @current_user do %>
            <.bottom_nav_link
              role="nav-notifications"
              active={@active == :notifications}
              icon="hero-bell"
              label="Notifications"
              navigate={~p"/notifications"}
              badge={@notifications_count}
            />

            <.bottom_nav_link
              role="nav-profile"
              active={@active == :profile}
              icon="hero-user-circle"
              label="Profile"
              navigate={profile_href(@current_user)}
            />
          <% else %>
            <.bottom_nav_link
              role="nav-login"
              active={false}
              icon="hero-arrow-right-on-rectangle"
              label="Login"
              navigate={~p"/login"}
            />

            <.bottom_nav_link
              role="nav-register"
              active={false}
              icon="hero-user-plus"
              label="Register"
              navigate={~p"/register"}
            />
          <% end %>
        </div>
      </nav>
    </section>
    """
  end

  attr :role, :string, required: true
  attr :active, :boolean, default: false
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :navigate, :string, required: true
  slot :inner_block

  defp nav_link(assigns) do
    ~H"""
    <.link
      data-role={@role}
      navigate={@navigate}
      class={[
        "group flex items-center gap-3 rounded-2xl px-3 py-2 text-sm font-semibold transition",
        @active &&
          "bg-slate-900 text-white shadow-sm shadow-slate-900/20 dark:bg-slate-100 dark:text-slate-900",
        !@active &&
          "text-slate-700 hover:bg-slate-900/5 hover:text-slate-900 dark:text-slate-200 dark:hover:bg-white/10 dark:hover:text-white"
      ]}
    >
      <.icon name={@icon} class={["size-5 opacity-80 transition group-hover:opacity-100"]} />
      <span class="min-w-0 truncate">{@label}</span>
      {render_slot(@inner_block)}
    </.link>
    """
  end

  attr :role, :string, required: true
  attr :active, :boolean, default: false
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :navigate, :string, required: true
  attr :badge, :integer, default: 0

  defp bottom_nav_link(assigns) do
    ~H"""
    <.link
      data-role={@role}
      navigate={@navigate}
      class={[
        "relative flex flex-1 items-center justify-center rounded-2xl px-3 py-3 text-slate-500 transition",
        @active &&
          "bg-slate-900 text-white shadow-sm shadow-slate-900/20 dark:bg-slate-100 dark:text-slate-900",
        !@active &&
          "hover:bg-slate-900/5 hover:text-slate-900 dark:text-slate-200 dark:hover:bg-white/10"
      ]}
      aria-label={@label}
    >
      <.icon name={@icon} class="size-5" />
      <span
        :if={@badge > 0 and @role == "nav-notifications"}
        class="absolute right-3 top-2 inline-flex min-w-5 items-center justify-center rounded-full bg-rose-600 px-1.5 py-0.5 text-[10px] font-semibold text-white"
      >
        {@badge}
      </span>
    </.link>
    """
  end

  defp timeline_href(%{id: _}), do: ~p"/?timeline=home"
  defp timeline_href(_user), do: ~p"/?timeline=public"

  defp profile_href(%{nickname: nickname}) when is_binary(nickname) and nickname != "" do
    ~p"/@#{nickname}"
  end

  defp profile_href(_user), do: ~p"/"

  defp avatar_src(user) when is_map(user) do
    user
    |> Map.get(:avatar_url)
    |> URL.absolute()
  end

  defp avatar_src(_user), do: nil

  defp display_name(user) when is_map(user) do
    Map.get(user, :name) || Map.get(user, :nickname) || "Unknown"
  end

  defp display_name(_user), do: "Unknown"

  defp nickname(user) when is_map(user), do: Map.get(user, :nickname) || "unknown"
  defp nickname(_user), do: "unknown"
end
