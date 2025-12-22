defmodule PleromaReduxWeb.NotificationsLive do
  use PleromaReduxWeb, :live_view

  alias PleromaRedux.HTML
  alias PleromaRedux.Notifications
  alias PleromaRedux.Objects
  alias PleromaRedux.User
  alias PleromaRedux.Users
  alias PleromaReduxWeb.ViewModels.Actor, as: ActorVM

  @page_size 20

  @impl true
  def mount(_params, session, socket) do
    current_user =
      case Map.get(session, "user_id") do
        nil -> nil
        id -> Users.get(id)
      end

    if connected?(socket) and match?(%User{}, current_user) do
      Notifications.subscribe(current_user.ap_id)
    end

    notifications = list_notifications(current_user, limit: @page_size)

    {:ok,
     socket
     |> assign(
       current_user: current_user,
       notifications_count: notifications_count(current_user),
       notifications_filter: "all",
       notifications_cursor: notifications_cursor(notifications),
       notifications_end?: length(notifications) < @page_size
     )
     |> stream(:notifications, decorate_notifications(notifications),
       dom_id: &notification_dom_id/1
     )}
  end

  @impl true
  def handle_info({:notification_created, activity}, socket) do
    case socket.assigns.current_user do
      %User{} ->
        entry = decorate_notification(activity)

        {:noreply,
         socket
         |> stream_insert(:notifications, entry, at: 0)
         |> assign(:notifications_count, socket.assigns.notifications_count + 1)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    cursor = socket.assigns.notifications_cursor

    cond do
      socket.assigns.notifications_end? ->
        {:noreply, socket}

      is_nil(cursor) ->
        {:noreply, assign(socket, notifications_end?: true)}

      true ->
        notifications =
          list_notifications(socket.assigns.current_user,
            limit: @page_size,
            max_id: cursor
          )

        socket =
          if notifications == [] do
            assign(socket, notifications_end?: true)
          else
            new_cursor = notifications_cursor(notifications)
            notifications_end? = length(notifications) < @page_size

            socket =
              Enum.reduce(decorate_notifications(notifications), socket, fn entry, socket ->
                stream_insert(socket, :notifications, entry, at: -1)
              end)

            assign(socket,
              notifications_cursor: new_cursor,
              notifications_end?: notifications_end?
            )
          end

        {:noreply, socket}
    end
  end

  def handle_event("set_notifications_filter", %{"filter" => filter}, socket) do
    filter = filter |> to_string() |> String.trim()

    if filter in ~w(all follows likes reposts) do
      {:noreply, assign(socket, notifications_filter: filter)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <AppShell.app_shell
        id="notifications-shell"
        nav_id="notifications-nav"
        main_id="notifications-main"
        active={:notifications}
        current_user={@current_user}
        notifications_count={@notifications_count}
      >
        <section class="space-y-4">
          <.card class="p-6">
            <div class="flex items-center justify-between gap-4">
              <div>
                <p class="text-xs uppercase tracking-[0.3em] text-slate-500 dark:text-slate-400">
                  Notifications
                </p>
                <h2 class="mt-2 font-display text-2xl text-slate-900 dark:text-slate-100">
                  Activity
                </h2>
              </div>
            </div>

            <div :if={@current_user} class="mt-4 flex flex-wrap items-center gap-2">
              <.filter_button
                filter="all"
                current={@notifications_filter}
                label="All"
                icon="hero-squares-2x2"
              />
              <.filter_button
                filter="follows"
                current={@notifications_filter}
                label="Follows"
                icon="hero-user-plus"
              />
              <.filter_button
                filter="likes"
                current={@notifications_filter}
                label="Likes"
                icon="hero-heart"
              />
              <.filter_button
                filter="reposts"
                current={@notifications_filter}
                label="Reposts"
                icon="hero-arrow-path"
              />
            </div>
          </.card>

          <%= if @current_user do %>
            <div
              id="notifications-list"
              data-role="notifications-list"
              data-filter={@notifications_filter}
              phx-update="stream"
              class="space-y-4"
            >
              <div
                id="notifications-empty"
                class="hidden only:block rounded-3xl border border-slate-200/80 bg-white/70 p-6 text-sm text-slate-600 shadow-sm shadow-slate-200/20 dark:border-slate-700/70 dark:bg-slate-950/50 dark:text-slate-300 dark:shadow-slate-900/30"
              >
                No notifications yet.
              </div>

              <.notification_item :for={{id, entry} <- @streams.notifications} id={id} entry={entry} />
            </div>

            <div :if={!@notifications_end?} class="flex justify-center py-2">
              <.button
                data-role="notifications-load-more"
                phx-click="load_more"
                phx-disable-with="Loading..."
                aria-label="Load more notifications"
                variant="secondary"
              >
                <.icon name="hero-chevron-down" class="size-4" /> Load more
              </.button>
            </div>
          <% else %>
            <.card class="p-6">
              <p
                data-role="notifications-auth-required"
                class="text-sm text-slate-600 dark:text-slate-300"
              >
                Sign in to view notifications.
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

  attr :filter, :string, required: true
  attr :current, :string, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true

  defp filter_button(assigns) do
    assigns = assign(assigns, active?: assigns.filter == assigns.current)

    ~H"""
    <button
      type="button"
      data-role="notifications-filter"
      data-filter={@filter}
      phx-click={set_filter_js(@filter)}
      aria-pressed={@active?}
      class={[
        "inline-flex items-center gap-2 rounded-full border px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] transition",
        @active? &&
          "border-slate-900 bg-slate-900 text-white shadow-lg shadow-slate-900/20 hover:bg-slate-800 dark:border-slate-100 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-white",
        !@active? &&
          "border-slate-200/80 bg-white/70 text-slate-700 hover:-translate-y-0.5 hover:bg-white dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:hover:bg-slate-950"
      ]}
    >
      <.icon name={@icon} class="size-4" />
      {@label}
    </button>
    """
  end

  attr :id, :string, required: true
  attr :entry, :map, required: true

  defp notification_item(assigns) do
    ~H"""
    <article
      id={@id}
      data-role="notification"
      data-type={@entry.type}
      class="rounded-3xl border border-white/80 bg-white/80 p-6 shadow-lg shadow-slate-200/30 backdrop-blur transition hover:-translate-y-0.5 hover:shadow-xl dark:border-slate-700/60 dark:bg-slate-900/70 dark:shadow-slate-900/50 motion-safe:animate-rise"
    >
      <div class="flex items-start gap-4">
        <.avatar size="sm" name={@entry.actor.display_name} src={@entry.actor.avatar_url} />

        <div class="min-w-0 flex-1 space-y-3">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p class="flex flex-wrap items-center gap-2 text-sm font-semibold text-slate-900 dark:text-slate-100">
                <.icon name={@entry.icon} class="size-4 text-slate-500 dark:text-slate-400" />
                <span class="truncate">{@entry.message}</span>
              </p>
              <p class="mt-1 text-xs text-slate-500 dark:text-slate-400">
                {@entry.actor.handle}
              </p>
            </div>

            <span class="shrink-0">
              <.time_ago at={@entry.notification.inserted_at} />
            </span>
          </div>

          <div
            :if={@entry.preview_html}
            class="rounded-2xl border border-slate-200/80 bg-white/70 p-4 text-sm text-slate-700 shadow-sm shadow-slate-200/20 dark:border-slate-700/70 dark:bg-slate-950/50 dark:text-slate-200 dark:shadow-slate-900/30"
          >
            {@entry.preview_html}
          </div>
        </div>
      </div>
    </article>
    """
  end

  defp set_filter_js(filter) when is_binary(filter) do
    JS.set_attribute({"data-filter", filter}, to: "#notifications-list")
    |> JS.push("set_notifications_filter", value: %{filter: filter})
  end

  defp list_notifications(nil, _opts), do: []

  defp list_notifications(%User{} = user, opts) when is_list(opts) do
    Notifications.list_for_user(user, opts)
  end

  defp decorate_notifications(notifications) when is_list(notifications) do
    Enum.map(notifications, &decorate_notification/1)
  end

  defp decorate_notification(%{type: type} = notification) when is_binary(type) do
    actor = ActorVM.card(notification.actor)

    {icon, message, preview_html} =
      case type do
        "Follow" ->
          {"hero-user-plus", "#{actor.display_name} followed you", nil}

        "Like" ->
          {"hero-heart", "#{actor.display_name} liked your post",
           note_preview(notification.object)}

        "Announce" ->
          {"hero-arrow-path", "#{actor.display_name} reposted your post",
           note_preview(notification.object)}

        _ ->
          {"hero-bell", "#{actor.display_name} sent activity", nil}
      end

    %{
      notification: notification,
      type: type,
      actor: actor,
      icon: icon,
      message: message,
      preview_html: preview_html
    }
  end

  defp note_preview(note_ap_id) when is_binary(note_ap_id) do
    case Objects.get_by_ap_id(note_ap_id) do
      %{type: "Note"} = object ->
        raw = object.data |> Map.get("content", "") |> to_string()

        format =
          case Map.get(object, :local) do
            false -> :html
            _ -> :text
          end

        raw
        |> HTML.to_safe_html(format: format)
        |> Phoenix.HTML.raw()

      _ ->
        nil
    end
  end

  defp note_preview(_note_ap_id), do: nil

  defp notifications_count(nil), do: 0

  defp notifications_count(%User{} = user) do
    user
    |> Notifications.list_for_user(limit: @page_size)
    |> length()
  end

  defp notifications_cursor([]), do: nil

  defp notifications_cursor(notifications) when is_list(notifications) do
    case List.last(notifications) do
      %{id: id} when is_integer(id) -> id
      _ -> nil
    end
  end

  defp notification_dom_id(%{notification: %{id: id}}) when is_integer(id),
    do: "notification-#{id}"

  defp notification_dom_id(_notification), do: Ecto.UUID.generate()
end
