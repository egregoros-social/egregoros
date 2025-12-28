defmodule EgregorosWeb.MessagesLive do
  use EgregorosWeb, :live_view

  alias Egregoros.DirectMessages
  alias Egregoros.Notifications
  alias Egregoros.Objects
  alias Egregoros.Publish
  alias Egregoros.Timeline
  alias Egregoros.User
  alias Egregoros.Users
  alias EgregorosWeb.ViewModels.Status, as: StatusVM

  @page_size 20

  @impl true
  def mount(_params, session, socket) do
    current_user =
      case Map.get(session, "user_id") do
        nil -> nil
        id -> Users.get(id)
      end

    if connected?(socket) and match?(%User{}, current_user) do
      Timeline.subscribe()
    end

    messages = DirectMessages.list_for_user(current_user, limit: @page_size)

    {:ok,
     socket
     |> assign(
       current_user: current_user,
       notifications_count: notifications_count(current_user),
       dm_form:
         Phoenix.Component.to_form(%{"recipient" => "", "content" => "", "e2ee_dm" => ""}, as: :dm),
       dm_cursor: cursor(messages),
       dm_end?: length(messages) < @page_size
     )
     |> stream(:messages, StatusVM.decorate_many(messages, current_user), dom_id: &message_dom_id/1)}
  end

  @impl true
  def handle_info({:post_created, post}, socket) do
    case socket.assigns.current_user do
      %User{} = user ->
        if include_dm?(post, user) do
          {:noreply, stream_insert(socket, :messages, StatusVM.decorate(post, user), at: 0)}
        else
          {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    cursor = socket.assigns.dm_cursor

    cond do
      socket.assigns.dm_end? ->
        {:noreply, socket}

      is_nil(cursor) ->
        {:noreply, assign(socket, dm_end?: true)}

      true ->
        messages =
          DirectMessages.list_for_user(socket.assigns.current_user,
            limit: @page_size,
            max_id: cursor
          )

        socket =
          if messages == [] do
            assign(socket, dm_end?: true)
          else
            current_user = socket.assigns.current_user
            new_cursor = cursor(messages)
            dm_end? = length(messages) < @page_size

            Enum.reduce(StatusVM.decorate_many(messages, current_user), socket, fn entry, socket ->
              stream_insert(socket, :messages, entry, at: -1)
            end)
            |> assign(dm_cursor: new_cursor, dm_end?: dm_end?)
          end

        {:noreply, socket}
    end
  end

  def handle_event("send_dm", %{"dm" => %{} = params}, socket) do
    recipient = params |> Map.get("recipient", "") |> to_string() |> String.trim()
    body = params |> Map.get("content", "") |> to_string() |> String.trim()
    e2ee_dm = params |> Map.get("e2ee_dm", "") |> to_string() |> String.trim()

    cond do
      not match?(%User{}, socket.assigns.current_user) ->
        {:noreply, put_flash(socket, :error, "Sign in to send messages.")}

      recipient == "" ->
        {:noreply, put_flash(socket, :error, "Pick a recipient.")}

      body == "" ->
        {:noreply, put_flash(socket, :error, "Message can't be empty.")}

      true ->
        {content, opts} = prepare_dm(recipient, body, e2ee_dm)

        case Publish.post_note(socket.assigns.current_user, content, opts) do
          {:ok, create} ->
            note = Objects.get_by_ap_id(create.object)

            socket =
              socket
              |> put_flash(:info, "Message sent.")
              |> assign(
                dm_form:
                  Phoenix.Component.to_form(
                    %{"recipient" => recipient, "content" => "", "e2ee_dm" => ""},
                    as: :dm
                  )
              )

            if note do
              {:noreply, stream_insert(socket, :messages, StatusVM.decorate(note, socket.assigns.current_user), at: 0)}
            else
              {:noreply, socket}
            end

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Could not send message.")}
        end
    end
  end

  def handle_event("send_dm", _params, socket) do
    {:noreply, put_flash(socket, :error, "Could not send message.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <AppShell.app_shell
        id="messages-shell"
        nav_id="messages-nav"
        main_id="messages-main"
        active={:messages}
        current_user={@current_user}
        notifications_count={@notifications_count}
      >
        <section class="space-y-4">
          <.card class="p-6">
            <p class="text-xs uppercase tracking-[0.3em] text-slate-500 dark:text-slate-400">
              Messages
            </p>
            <h2 class="mt-2 font-display text-2xl text-slate-900 dark:text-slate-100">
              Direct
            </h2>
          </.card>

          <%= if @current_user do %>
            <.card class="p-6">
              <.form
                for={@dm_form}
                id="dm-form"
                phx-submit="send_dm"
                phx-hook="E2EEDMComposer"
                data-role="dm-composer"
                data-user-ap-id={@current_user.ap_id}
                class="space-y-4"
              >
                <input
                  type="text"
                  name="dm[e2ee_dm]"
                  value={@dm_form.params["e2ee_dm"] || ""}
                  data-role="dm-e2ee-payload"
                  class="hidden"
                  aria-hidden="true"
                  tabindex="-1"
                />

                <p
                  data-role="dm-e2ee-feedback"
                  class="hidden rounded-lg border border-slate-200 bg-slate-50 px-3 py-2 text-sm text-slate-700 dark:border-slate-700 dark:bg-slate-900/40 dark:text-slate-200"
                >
                </p>

                <div class="space-y-2">
                  <label class="block text-sm font-semibold text-slate-700 dark:text-slate-200">
                    To
                  </label>
                  <input
                    type="text"
                    name="dm[recipient]"
                    value={@dm_form.params["recipient"] || ""}
                    placeholder="@alice or @alice@remote.example"
                    class="w-full rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm text-slate-900 shadow-sm focus:border-violet-500 focus:outline-none focus:ring-2 focus:ring-violet-200 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-100 dark:focus:border-violet-400 dark:focus:ring-violet-900/40"
                  />
                </div>

                <div class="space-y-2">
                  <label class="block text-sm font-semibold text-slate-700 dark:text-slate-200">
                    Message
                  </label>
                  <textarea
                    name="dm[content]"
                    rows="4"
                    placeholder="Write a direct message…"
                    class="w-full resize-none rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm text-slate-900 shadow-sm focus:border-violet-500 focus:outline-none focus:ring-2 focus:ring-violet-200 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-100 dark:focus:border-violet-400 dark:focus:ring-violet-900/40"
                  ><%= @dm_form.params["content"] || "" %></textarea>
                </div>

                <div class="flex justify-end">
                  <.button type="submit" phx-disable-with="Sending...">
                    Send
                  </.button>
                </div>
              </.form>
            </.card>

            <div
              id="messages-list"
              phx-update="stream"
              data-role="messages-list"
              class="space-y-4"
            >
              <div
                id="messages-empty"
                class="hidden only:block rounded-3xl border border-slate-200/80 bg-white/70 p-6 text-sm text-slate-600 shadow-sm shadow-slate-200/20 dark:border-slate-700/70 dark:bg-slate-950/50 dark:text-slate-300 dark:shadow-slate-900/30"
              >
                No direct messages yet.
              </div>

              <StatusCard.status_card
                :for={{id, entry} <- @streams.messages}
                id={id}
                entry={entry}
                current_user={@current_user}
                reply_mode={:navigate}
              />
            </div>

            <div :if={!@dm_end?} class="flex justify-center py-2">
              <.button
                data-role="messages-load-more"
                phx-click="load_more"
                phx-disable-with="Loading..."
                aria-label="Load more messages"
                variant="secondary"
              >
                <.icon name="hero-chevron-down" class="size-4" /> Load more
              </.button>
            </div>
          <% else %>
            <.card class="p-6">
              <p
                data-role="messages-auth-required"
                class="text-sm text-slate-600 dark:text-slate-300"
              >
                Sign in to view direct messages.
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

  defp include_dm?(%{type: "Note"} = note, %User{} = current_user) do
    DirectMessages.direct?(note) and Objects.visible_to?(note, current_user)
  end

  defp include_dm?(_note, _current_user), do: false

  defp cursor([]), do: nil

  defp cursor(messages) when is_list(messages) do
    case List.last(messages) do
      %{id: id} when is_integer(id) -> id
      _ -> nil
    end
  end

  defp message_dom_id(%{object: %{id: id}}) when is_integer(id), do: "dm-#{id}"
  defp message_dom_id(_), do: Ecto.UUID.generate()

  defp normalize_dm_content(recipient, body) when is_binary(recipient) and is_binary(body) do
    recipient =
      recipient
      |> String.trim()
      |> String.trim_leading("@")

    if recipient == "" do
      body
    else
      "@" <> recipient <> " " <> body
    end
  end

  defp prepare_dm(recipient, body, e2ee_dm) when is_binary(recipient) and is_binary(body) do
    e2ee_dm = if is_binary(e2ee_dm), do: String.trim(e2ee_dm), else: ""

    with true <- e2ee_dm != "",
         {:ok, %{} = payload} <- Jason.decode(e2ee_dm) do
      content = normalize_dm_content(recipient, "Encrypted message")
      {content, visibility: "direct", e2ee_dm: payload}
    else
      _ ->
        content = normalize_dm_content(recipient, body)
        {content, visibility: "direct"}
    end
  end

  defp notifications_count(nil), do: 0

  defp notifications_count(%User{} = user) do
    user
    |> Notifications.list_for_user(limit: 20)
    |> length()
  end
end
