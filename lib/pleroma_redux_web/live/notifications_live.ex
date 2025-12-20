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

    notifications = list_notifications(current_user, limit: @page_size)

    {:ok,
     socket
     |> assign(
       current_user: current_user,
       notifications_count: notifications_count(current_user),
       notifications_cursor: notifications_cursor(notifications),
       notifications_end?: length(notifications) < @page_size
     )
     |> stream(:notifications, decorate_notifications(notifications),
       dom_id: &notification_dom_id/1
     )}
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
          </.card>

          <%= if @current_user do %>
            <div id="notifications-list" phx-update="stream" class="space-y-4">
              <div
                id="notifications-empty"
                class="hidden only:block rounded-3xl border border-slate-200/80 bg-white/70 p-6 text-sm text-slate-600 shadow-sm shadow-slate-200/20 dark:border-slate-700/70 dark:bg-slate-950/50 dark:text-slate-300 dark:shadow-slate-900/30"
              >
                No notifications yet.
              </div>

              <.notification_item :for={{id, entry} <- @streams.notifications} id={id} entry={entry} />
            </div>

            <div :if={!@notifications_end?} class="flex justify-center py-2">
              <button
                type="button"
                data-role="notifications-load-more"
                phx-click="load_more"
                phx-disable-with="Loading..."
                class="inline-flex items-center justify-center gap-2 rounded-full border border-slate-200/80 bg-white/70 px-6 py-3 text-sm font-semibold text-slate-700 shadow-sm shadow-slate-200/20 transition hover:-translate-y-0.5 hover:bg-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:shadow-slate-900/40 dark:hover:bg-slate-950"
                aria-label="Load more notifications"
              >
                <.icon name="hero-chevron-down" class="size-4" /> Load more
              </button>
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

  attr :id, :string, required: true
  attr :entry, :map, required: true

  defp notification_item(assigns) do
    ~H"""
    <article
      id={@id}
      data-role="notification"
      data-type={@entry.type}
      class="rounded-3xl border border-white/80 bg-white/80 p-6 shadow-lg shadow-slate-200/30 backdrop-blur transition hover:-translate-y-0.5 hover:shadow-xl dark:border-slate-700/60 dark:bg-slate-900/70 dark:shadow-slate-900/50 animate-rise"
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

            <span class="shrink-0 text-xs text-slate-400 dark:text-slate-500">
              {format_time(@entry.notification.inserted_at)}
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

  defp format_time(_), do: ""
end
