defmodule PleromaReduxWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use PleromaReduxWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_user, :any,
    default: nil,
    doc: "the currently signed-in user (optional)"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="relative min-h-screen overflow-hidden bg-gradient-to-br from-amber-50 via-white to-slate-100 text-slate-900 dark:from-slate-950 dark:via-slate-900 dark:to-slate-950 dark:text-slate-100">
      <div class="pointer-events-none absolute -top-40 right-10 h-72 w-72 rounded-full bg-amber-200/60 blur-3xl dark:bg-sky-500/20">
      </div>
      <div class="pointer-events-none absolute -bottom-48 left-6 h-80 w-80 rounded-full bg-rose-200/60 blur-3xl dark:bg-fuchsia-500/20">
      </div>

      <div class="relative mx-auto max-w-6xl px-6 py-10">
        <header class="flex flex-col gap-6 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <p class="text-xs uppercase tracking-[0.35em] text-slate-500 dark:text-slate-400">
              Pleroma Redux
            </p>
            <h1 class="mt-2 font-display text-3xl sm:text-4xl">Signal feed</h1>
            <p class="mt-2 max-w-lg text-sm text-slate-600 dark:text-slate-300">
              A reduced federation core with a live, opinionated front door.
            </p>
          </div>
          <div class="flex items-center gap-4">
            <a
              href="https://docs.joinmastodon.org/client/intro/"
              class="text-xs uppercase tracking-[0.25em] text-slate-500 transition hover:text-slate-900 dark:text-slate-400 dark:hover:text-slate-100"
            >
              Mastodon API
            </a>
            <%= if @current_user do %>
              <a
                href={~p"/settings"}
                class="hidden text-xs uppercase tracking-[0.25em] text-slate-500 transition hover:text-slate-900 dark:text-slate-400 dark:hover:text-slate-100 sm:block"
              >
                Settings
              </a>
              <a
                href={~p"/logout"}
                class="hidden text-xs uppercase tracking-[0.25em] text-slate-500 transition hover:text-slate-900 dark:text-slate-400 dark:hover:text-slate-100 sm:block"
              >
                {@current_user.nickname} · Logout
              </a>
            <% else %>
              <a
                href={~p"/login"}
                class="hidden text-xs uppercase tracking-[0.25em] text-slate-500 transition hover:text-slate-900 dark:text-slate-400 dark:hover:text-slate-100 sm:block"
              >
                Login
              </a>
              <a
                href={~p"/register"}
                class="hidden text-xs uppercase tracking-[0.25em] text-slate-500 transition hover:text-slate-900 dark:text-slate-400 dark:hover:text-slate-100 sm:block"
              >
                Register
              </a>
            <% end %>
            <.theme_toggle />
          </div>
        </header>

        <main class="mt-10">
          {render_slot(@inner_block)}
        </main>
      </div>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div
      id={@id}
      aria-live="polite"
      class="pointer-events-none fixed inset-x-0 top-0 z-50 flex flex-col items-end gap-3 px-4 pt-4 sm:inset-auto sm:top-6 sm:right-6 sm:px-0 sm:pt-0"
    >
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="relative flex items-center rounded-full border border-slate-200/70 bg-white/70 p-1 shadow-sm shadow-slate-200/30 backdrop-blur transition dark:border-slate-700/70 dark:bg-slate-900/70 dark:shadow-slate-900/40">
      <div class="absolute inset-y-1 w-10 rounded-full bg-slate-900 text-slate-100 transition-all duration-300 [[data-theme-mode=system]_&]:translate-x-0 [[data-theme-mode=light]_&]:translate-x-10 [[data-theme-mode=dark]_&]:translate-x-20 dark:bg-slate-100 dark:text-slate-900">
      </div>

      <button
        class="relative z-10 flex h-8 w-10 items-center justify-center text-slate-500 transition hover:text-slate-900 dark:text-slate-400 dark:hover:text-slate-100"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4" />
      </button>

      <button
        class="relative z-10 flex h-8 w-10 items-center justify-center text-slate-500 transition hover:text-slate-900 dark:text-slate-400 dark:hover:text-slate-100"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4" />
      </button>

      <button
        class="relative z-10 flex h-8 w-10 items-center justify-center text-slate-500 transition hover:text-slate-900 dark:text-slate-400 dark:hover:text-slate-100"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4" />
      </button>
    </div>
    """
  end
end
