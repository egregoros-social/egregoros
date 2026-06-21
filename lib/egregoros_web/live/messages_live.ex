defmodule EgregorosWeb.MessagesLive do
  use EgregorosWeb, :live_view

  alias Egregoros.CustomEmojis
  alias Egregoros.DirectMessages
  alias Egregoros.E2EE.ActorKeys
  alias Egregoros.HTML
  alias Egregoros.Markers
  alias Egregoros.Notifications
  alias Egregoros.Objects
  alias Egregoros.Publish
  alias Egregoros.User
  alias Egregoros.Users
  alias EgregorosWeb.MentionAutocomplete
  alias EgregorosWeb.URL
  alias EgregorosWeb.ViewModels.Actor

  @conversations_page_size 40
  @messages_page_size 40
  @as_public "https://www.w3.org/ns/activitystreams#Public"
  @recipient_fields ~w(to cc bto bcc audience)
  @dm_marker_prefix "dm:v1:"

  @impl true
  def mount(_params, session, socket) do
    current_user =
      case Map.get(session, "user_id") do
        nil -> nil
        id -> Users.get(id)
      end

    if connected?(socket) and match?(%User{}, current_user) do
      Phoenix.PubSub.subscribe(
        Egregoros.PubSub,
        Egregoros.Timeline.user_topic(current_user.ap_id)
      )
    end

    {conversations, conversations_seen_peers, conversations_max_id, conversations_has_more?} =
      case current_user do
        %User{} = user -> conversations_page(user, MapSet.new())
        _ -> {[], MapSet.new(), nil, false}
      end

    dm_markers =
      case current_user do
        %User{} = user -> dm_markers_for_conversations(user, conversations)
        _ -> %{}
      end

    selected_peer_ap_id =
      case conversations do
        [%{peer: %{ap_id: ap_id}} | _] when is_binary(ap_id) and ap_id != "" -> ap_id
        _ -> nil
      end

    selected_peer =
      if is_binary(selected_peer_ap_id), do: Actor.card(selected_peer_ap_id), else: nil

    messages =
      case {current_user, selected_peer_ap_id} do
        {%User{}, ap_id} when is_binary(ap_id) and ap_id != "" ->
          current_user
          |> DirectMessages.list_conversation(ap_id, limit: @messages_page_size)
          |> Enum.reverse()

        _ ->
          []
      end

    conversation_e2ee? = Enum.any?(messages, &encrypted_message?/1)

    dm_peer_e2ee_keys =
      case selected_peer_ap_id do
        ap_id when is_binary(ap_id) and ap_id != "" ->
          case ActorKeys.list_actor_keys(ap_id) do
            {:ok, keys} when is_list(keys) -> keys
            _ -> []
          end

        _ ->
          []
      end

    dm_peer_supports_e2ee? = dm_peer_e2ee_keys != []

    chat_messages_oldest_id =
      case List.first(messages) do
        %{id: id} when is_binary(id) -> id
        _ -> nil
      end

    chat_messages_has_more? =
      length(messages) == @messages_page_size and is_binary(chat_messages_oldest_id)

    dm_markers =
      case {current_user, List.first(conversations)} do
        {%User{} = user, %{peer: %{ap_id: peer_ap_id}, last_message: %{id: id}}}
        when is_binary(peer_ap_id) and peer_ap_id != "" and is_binary(id) ->
          mark_dm_conversation_read(user, peer_ap_id, id, dm_markers)

        _ ->
          dm_markers
      end

    recipient =
      case selected_peer do
        %{handle: handle} when is_binary(handle) -> handle
        _ -> ""
      end

    dm_form =
      Phoenix.Component.to_form(%{"recipient" => recipient, "content" => "", "e2ee_dm" => ""},
        as: :dm
      )

    {:ok,
     socket
     |> assign(
       current_user: current_user,
       dm_markers: dm_markers,
       dm_peer_e2ee_keys: dm_peer_e2ee_keys,
       dm_peer_supports_e2ee?: dm_peer_supports_e2ee?,
       chat_messages_has_more?: chat_messages_has_more?,
       chat_messages_oldest_id: chat_messages_oldest_id,
       conversations_has_more?: conversations_has_more?,
       conversations_max_id: conversations_max_id,
       conversations_seen_peers: conversations_seen_peers,
       notifications_count: notifications_count(current_user),
       recipient_suggestions: [],
       selected_peer_ap_id: selected_peer_ap_id,
       selected_peer: selected_peer,
       conversation_e2ee?: conversation_e2ee?,
       dm_form: dm_form
     )
     |> stream(:conversations, conversations, dom_id: &conversation_dom_id/1)
     |> stream(:chat_messages, messages, dom_id: &message_dom_id/1)}
  end

  @impl true
  def handle_info({:post_created, post}, socket) do
    case socket.assigns.current_user do
      %User{} = user ->
        if include_dm?(post, user) do
          peer_ap_id = peer_ap_id_for_dm(post, user.ap_id)

          {conversations, conversations_seen_peers, conversations_max_id, conversations_has_more?} =
            conversations_page(user, MapSet.new())

          dm_markers = dm_markers_for_conversations(user, conversations)

          socket =
            socket
            |> assign(
              conversations_has_more?: conversations_has_more?,
              conversations_max_id: conversations_max_id,
              conversations_seen_peers: conversations_seen_peers,
              dm_markers: dm_markers
            )
            |> stream(:conversations, conversations, reset: true)

          socket =
            if is_binary(peer_ap_id) and peer_ap_id == socket.assigns.selected_peer_ap_id do
              dm_markers =
                mark_dm_conversation_read(user, peer_ap_id, post.id, socket.assigns.dm_markers)

              socket
              |> assign(:dm_markers, dm_markers)
              |> stream_insert(:chat_messages, post, at: -1)
              |> then(fn socket ->
                if encrypted_message?(post),
                  do: assign(socket, :conversation_e2ee?, true),
                  else: socket
              end)
            else
              socket
            end

          {:noreply, socket}
        else
          {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_conversation", %{"peer" => peer_ap_id}, socket) do
    peer_ap_id = peer_ap_id |> to_string() |> String.trim()

    case socket.assigns.current_user do
      %User{} = user when peer_ap_id != "" ->
        selected_peer = Actor.card(peer_ap_id)

        recipient = selected_peer.handle

        dm_form =
          Phoenix.Component.to_form(%{"recipient" => recipient, "content" => "", "e2ee_dm" => ""},
            as: :dm
          )

        messages =
          user
          |> DirectMessages.list_conversation(peer_ap_id, limit: @messages_page_size)
          |> Enum.reverse()

        conversation_e2ee? = Enum.any?(messages, &encrypted_message?/1)

        chat_messages_oldest_id =
          case List.first(messages) do
            %{id: id} when is_binary(id) -> id
            _ -> nil
          end

        chat_messages_has_more? =
          length(messages) == @messages_page_size and is_binary(chat_messages_oldest_id)

        dm_peer_e2ee_keys =
          case ActorKeys.list_actor_keys(peer_ap_id) do
            {:ok, keys} when is_list(keys) -> keys
            _ -> []
          end

        dm_peer_supports_e2ee? = dm_peer_e2ee_keys != []

        dm_markers =
          case List.last(messages) do
            %{id: id} when is_binary(id) ->
              mark_dm_conversation_read(user, peer_ap_id, id, socket.assigns.dm_markers)

            _ ->
              socket.assigns.dm_markers
          end

        {:noreply,
         socket
         |> assign(
           selected_peer_ap_id: peer_ap_id,
           selected_peer: selected_peer,
           conversation_e2ee?: conversation_e2ee?,
           dm_peer_e2ee_keys: dm_peer_e2ee_keys,
           dm_peer_supports_e2ee?: dm_peer_supports_e2ee?,
           chat_messages_has_more?: chat_messages_has_more?,
           chat_messages_oldest_id: chat_messages_oldest_id,
           dm_markers: dm_markers,
           recipient_suggestions: [],
           dm_form: dm_form
         )
         |> stream(:chat_messages, messages, reset: true)
         |> then(fn socket ->
           case List.last(messages) do
             %{id: id} = last_message when is_binary(id) ->
               stream_insert(socket, :conversations, %{
                 peer: selected_peer,
                 last_message: last_message
               })

             _ ->
               socket
           end
         end)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("select_conversation", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("new_chat", _params, socket) do
    case socket.assigns.current_user do
      %User{} ->
        dm_form =
          Phoenix.Component.to_form(%{"recipient" => "", "content" => "", "e2ee_dm" => ""},
            as: :dm
          )

        {:noreply,
         socket
         |> assign(
           selected_peer_ap_id: nil,
           selected_peer: nil,
           conversation_e2ee?: false,
           dm_peer_e2ee_keys: [],
           dm_peer_supports_e2ee?: false,
           chat_messages_has_more?: false,
           chat_messages_oldest_id: nil,
           recipient_suggestions: [],
           dm_form: dm_form
         )
         |> stream(:chat_messages, [], reset: true)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("dm_change", %{"dm" => %{} = params}, socket) do
    dm_form = Phoenix.Component.to_form(params, as: :dm)

    suggestions =
      case {socket.assigns.current_user, socket.assigns.selected_peer} do
        {%User{} = user, nil} ->
          recipient = params |> Map.get("recipient", "") |> to_string() |> String.trim()

          if recipient == "" do
            []
          else
            MentionAutocomplete.suggestions(recipient, limit: 8, current_user: user)
          end

        _ ->
          []
      end

    {:noreply,
     socket
     |> assign(dm_form: dm_form, recipient_suggestions: suggestions)}
  end

  def handle_event("dm_change", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("pick_recipient", %{"ap_id" => ap_id, "handle" => handle}, socket) do
    ap_id = ap_id |> to_string() |> String.trim()
    handle = handle |> to_string() |> String.trim()

    case socket.assigns.current_user do
      %User{} = user when ap_id != "" ->
        selected_peer = Actor.card(ap_id)

        messages =
          user
          |> DirectMessages.list_conversation(ap_id, limit: @messages_page_size)
          |> Enum.reverse()

        conversation_e2ee? = Enum.any?(messages, &encrypted_message?/1)

        chat_messages_oldest_id =
          case List.first(messages) do
            %{id: id} when is_binary(id) -> id
            _ -> nil
          end

        chat_messages_has_more? =
          length(messages) == @messages_page_size and is_binary(chat_messages_oldest_id)

        dm_peer_e2ee_keys =
          case ActorKeys.list_actor_keys(ap_id) do
            {:ok, keys} when is_list(keys) -> keys
            _ -> []
          end

        dm_peer_supports_e2ee? = dm_peer_e2ee_keys != []

        dm_form =
          Phoenix.Component.to_form(%{"recipient" => handle, "content" => "", "e2ee_dm" => ""},
            as: :dm
          )

        dm_markers =
          case List.last(messages) do
            %{id: id} when is_binary(id) ->
              mark_dm_conversation_read(user, ap_id, id, socket.assigns.dm_markers)

            _ ->
              socket.assigns.dm_markers
          end

        {:noreply,
         socket
         |> assign(
           selected_peer_ap_id: ap_id,
           selected_peer: selected_peer,
           conversation_e2ee?: conversation_e2ee?,
           dm_peer_e2ee_keys: dm_peer_e2ee_keys,
           dm_peer_supports_e2ee?: dm_peer_supports_e2ee?,
           chat_messages_has_more?: chat_messages_has_more?,
           chat_messages_oldest_id: chat_messages_oldest_id,
           dm_markers: dm_markers,
           recipient_suggestions: [],
           dm_form: dm_form
         )
         |> stream(:chat_messages, messages, reset: true)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("pick_recipient", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("load_older_messages", _params, socket) do
    case {socket.assigns.current_user, socket.assigns.selected_peer_ap_id,
          socket.assigns.chat_messages_oldest_id} do
      {%User{} = user, peer_ap_id, oldest_id}
      when is_binary(peer_ap_id) and peer_ap_id != "" and is_binary(oldest_id) ->
        older_messages =
          DirectMessages.list_conversation(user, peer_ap_id,
            max_id: oldest_id,
            limit: @messages_page_size
          )

        socket =
          Enum.reduce(older_messages, socket, fn message, socket ->
            stream_insert(socket, :chat_messages, message, at: 0)
          end)

        chat_messages_oldest_id =
          case List.last(older_messages) do
            %{id: id} when is_binary(id) -> id
            _ -> oldest_id
          end

        chat_messages_has_more? =
          length(older_messages) == @messages_page_size and is_binary(chat_messages_oldest_id)

        socket =
          if socket.assigns.conversation_e2ee? do
            socket
          else
            if Enum.any?(older_messages, &encrypted_message?/1),
              do: assign(socket, :conversation_e2ee?, true),
              else: socket
          end

        {:noreply,
         socket
         |> assign(
           chat_messages_has_more?: chat_messages_has_more?,
           chat_messages_oldest_id: chat_messages_oldest_id
         )}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("load_more_conversations", _params, socket) do
    case {socket.assigns.current_user, socket.assigns.conversations_seen_peers,
          socket.assigns.conversations_max_id} do
      {%User{} = user, %MapSet{} = seen_peers, max_id} when is_binary(max_id) ->
        {conversations, seen_peers, conversations_max_id, conversations_has_more?} =
          conversations_page(user, seen_peers, max_id: max_id)

        dm_markers =
          socket.assigns.dm_markers
          |> Map.merge(dm_markers_for_conversations(user, conversations))

        {:noreply,
         socket
         |> assign(
           conversations_has_more?: conversations_has_more?,
           conversations_max_id: conversations_max_id,
           conversations_seen_peers: seen_peers,
           dm_markers: dm_markers
         )
         |> stream(:conversations, conversations)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
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
            message = Objects.get_by_ap_id(create.object)

            {peer_ap_id, selected_peer} =
              case {socket.assigns.current_user, message} do
                {%User{ap_id: ap_id}, %{} = message} when is_binary(ap_id) ->
                  peer_ap_id = peer_ap_id_for_dm(message, ap_id)

                  selected_peer =
                    if is_binary(peer_ap_id) and peer_ap_id != "" do
                      Actor.card(peer_ap_id)
                    else
                      nil
                    end

                  {peer_ap_id, selected_peer}

                _ ->
                  {nil, nil}
              end

            recipient =
              case selected_peer do
                %{handle: handle} when is_binary(handle) -> handle
                _ -> recipient
              end

            dm_form =
              Phoenix.Component.to_form(
                %{"recipient" => recipient, "content" => "", "e2ee_dm" => ""},
                as: :dm
              )

            {conversations, conversations_seen_peers, conversations_max_id,
             conversations_has_more?} =
              conversations_page(socket.assigns.current_user, MapSet.new())

            dm_markers = dm_markers_for_conversations(socket.assigns.current_user, conversations)

            dm_peer_e2ee_keys =
              case peer_ap_id do
                ap_id when is_binary(ap_id) and ap_id != "" ->
                  case ActorKeys.list_actor_keys(ap_id) do
                    {:ok, keys} when is_list(keys) -> keys
                    _ -> []
                  end

                _ ->
                  []
              end

            dm_peer_supports_e2ee? = dm_peer_e2ee_keys != []

            socket =
              socket
              |> assign(
                conversations_has_more?: conversations_has_more?,
                conversations_max_id: conversations_max_id,
                conversations_seen_peers: conversations_seen_peers,
                dm_markers: dm_markers,
                selected_peer_ap_id: peer_ap_id,
                selected_peer: selected_peer,
                dm_peer_e2ee_keys: dm_peer_e2ee_keys,
                dm_peer_supports_e2ee?: dm_peer_supports_e2ee?,
                recipient_suggestions: [],
                dm_form: dm_form
              )
              |> stream(:conversations, conversations, reset: true)

            socket =
              if is_binary(peer_ap_id) and peer_ap_id != "" do
                messages =
                  socket.assigns.current_user
                  |> DirectMessages.list_conversation(peer_ap_id, limit: @messages_page_size)
                  |> Enum.reverse()

                chat_messages_oldest_id =
                  case List.first(messages) do
                    %{id: id} when is_binary(id) -> id
                    _ -> nil
                  end

                chat_messages_has_more? =
                  length(messages) == @messages_page_size and is_binary(chat_messages_oldest_id)

                dm_markers =
                  case List.last(messages) do
                    %{id: id} when is_binary(id) ->
                      mark_dm_conversation_read(
                        socket.assigns.current_user,
                        peer_ap_id,
                        id,
                        socket.assigns.dm_markers
                      )

                    _ ->
                      socket.assigns.dm_markers
                  end

                socket
                |> assign(:conversation_e2ee?, Enum.any?(messages, &encrypted_message?/1))
                |> assign(:dm_markers, dm_markers)
                |> assign(:dm_peer_e2ee_keys, dm_peer_e2ee_keys)
                |> assign(:chat_messages_has_more?, chat_messages_has_more?)
                |> assign(:chat_messages_oldest_id, chat_messages_oldest_id)
                |> assign(:recipient_suggestions, [])
                |> stream(:chat_messages, messages, reset: true)
              else
                socket
                |> assign(:conversation_e2ee?, false)
                |> assign(:chat_messages_has_more?, false)
                |> assign(:chat_messages_oldest_id, nil)
                |> assign(:dm_peer_e2ee_keys, [])
              end

            {:noreply, socket}

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
          <%= if @current_user do %>
            <div class="grid gap-4 lg:grid-cols-[18rem_1fr]">
              <aside class="border-2 border-[color:var(--border-default)] bg-[color:var(--bg-base)]">
                <header class="flex items-center justify-between border-b-2 border-[color:var(--border-default)] px-4 py-3">
                  <h2 class="text-xs font-bold uppercase tracking-widest text-[color:var(--text-muted)]">
                    Messages
                  </h2>
                  <button
                    type="button"
                    data-role="dm-new-chat"
                    phx-click="new_chat"
                    class="border-2 border-[color:var(--border-default)] bg-[color:var(--text-primary)] px-2 py-1 text-xs font-bold uppercase text-[color:var(--bg-base)] transition hover:shadow-[3px_3px_0_var(--border-default)] hover:-translate-x-0.5 hover:-translate-y-0.5"
                  >
                    + New
                  </button>
                </header>

                <div
                  data-role="dm-conversations"
                  id="dm-conversations"
                  phx-update="stream"
                  class="max-h-[70vh] overflow-y-auto"
                >
                  <button
                    :for={{id, conversation} <- @streams.conversations}
                    id={id}
                    type="button"
                    data-role="dm-conversation"
                    data-peer-handle={conversation.peer.handle}
                    phx-click="select_conversation"
                    phx-value-peer={conversation.peer.ap_id}
                    class={[
                      "flex w-full cursor-pointer items-start gap-3 border-b border-[color:var(--border-muted)] px-4 py-4 text-left transition hover:bg-[color:var(--bg-subtle)] focus-visible:outline-none focus-brutal",
                      conversation.peer.ap_id == @selected_peer_ap_id &&
                        "bg-[color:var(--bg-subtle)] border-l-4 border-l-[color:var(--text-primary)] pl-3"
                    ]}
                  >
                    <span class="mt-0.5 inline-flex h-9 w-9 shrink-0 items-center justify-center overflow-hidden border-2 border-[color:var(--border-default)] bg-[color:var(--bg-subtle)] font-bold">
                      <%= if conversation.peer.avatar_url do %>
                        <img
                          src={conversation.peer.avatar_url}
                          alt=""
                          class="h-full w-full object-cover"
                        />
                      <% else %>
                        {avatar_initial(conversation.peer.display_name)}
                      <% end %>
                    </span>
                    <span class="min-w-0 flex-1">
                      <span class="flex items-start justify-between gap-3">
                        <span class="block min-w-0 truncate font-bold text-[color:var(--text-primary)]">
                          {conversation.peer.display_name}
                        </span>
                        <span class="flex shrink-0 items-center gap-2">
                          <span
                            :if={encrypted_message?(conversation.last_message)}
                            data-role="dm-conversation-e2ee"
                            class="inline-flex items-center text-[color:var(--success)]"
                            title="Last message is encrypted"
                          >
                            <.icon name="hero-lock-closed" class="size-4" />
                          </span>
                          <span
                            :if={conversation_unread?(conversation, @dm_markers, @current_user)}
                            data-role="dm-conversation-unread"
                            class="inline-flex h-2 w-2 rounded-full bg-[color:var(--accent)]"
                            title="Unread"
                          />
                          <.time_ago
                            at={dm_last_message_at(conversation.last_message)}
                            data_role="dm-conversation-time"
                            class="text-[10px]"
                          />
                        </span>
                      </span>
                      <span class="mt-0.5 block truncate font-mono text-xs text-[color:var(--text-muted)]">
                        {conversation.peer.handle}
                      </span>
                      <span
                        data-role="dm-conversation-preview"
                        class="mt-1 block truncate text-xs text-[color:var(--text-muted)]"
                      >
                        {dm_preview_text(conversation.last_message, @current_user)}
                      </span>
                    </span>
                  </button>
                </div>

                <button
                  :if={@conversations_has_more?}
                  type="button"
                  data-role="dm-load-more-conversations"
                  phx-click="load_more_conversations"
                  class="w-full border-t border-[color:var(--border-muted)] bg-[color:var(--bg-base)] px-4 py-3 text-center text-xs font-bold uppercase tracking-widest text-[color:var(--text-primary)] transition hover:bg-[color:var(--bg-subtle)] focus-visible:outline-none focus-brutal"
                >
                  Load more
                </button>
              </aside>

              <main class="flex h-[70vh] flex-col border-2 border-[color:var(--border-default)] bg-[color:var(--bg-base)]">
                <header class="flex shrink-0 items-center justify-between border-b-2 border-[color:var(--border-default)] px-5 py-4">
                  <%= if @selected_peer do %>
                    <div class="flex min-w-0 items-center gap-3">
                      <span class="inline-flex h-10 w-10 shrink-0 items-center justify-center overflow-hidden border-2 border-[color:var(--border-default)] bg-[color:var(--bg-subtle)] font-bold">
                        <%= if @selected_peer.avatar_url do %>
                          <img
                            src={@selected_peer.avatar_url}
                            alt=""
                            class="h-full w-full object-cover"
                          />
                        <% else %>
                          {avatar_initial(@selected_peer.display_name)}
                        <% end %>
                      </span>
                      <div class="min-w-0">
                        <p class="truncate font-bold text-[color:var(--text-primary)]">
                          {@selected_peer.display_name}
                        </p>
                        <p
                          data-role="dm-chat-peer-handle"
                          class="truncate font-mono text-xs text-[color:var(--text-muted)]"
                        >
                          {@selected_peer.handle}
                        </p>
                      </div>
                    </div>

                    <span
                      :if={@conversation_e2ee?}
                      data-role="dm-e2ee-badge"
                      class="inline-flex items-center gap-2 border border-[color:var(--success)] bg-[color:var(--success-subtle)] px-3 py-1 font-mono text-[10px] font-bold uppercase tracking-widest text-[color:var(--success)]"
                    >
                      <.icon name="hero-lock-closed" class="size-4" /> E2EE
                    </span>
                  <% else %>
                    <div class="min-w-0">
                      <p class="font-bold text-[color:var(--text-primary)]">New encrypted chat</p>
                      <p class="font-mono text-xs text-[color:var(--text-muted)]">
                        Pick a recipient to start.
                      </p>
                    </div>

                    <span
                      :if={@conversation_e2ee?}
                      data-role="dm-e2ee-badge"
                      class="inline-flex items-center gap-2 border border-[color:var(--success)] bg-[color:var(--success-subtle)] px-3 py-1 font-mono text-[10px] font-bold uppercase tracking-widest text-[color:var(--success)]"
                    >
                      <.icon name="hero-shield-check" class="size-4" /> E2EE
                    </span>
                  <% end %>
                </header>

                <button
                  :if={@chat_messages_has_more?}
                  id="dm-load-older"
                  type="button"
                  data-role="dm-load-older"
                  phx-click="load_older_messages"
                  class="shrink-0 border-b-2 border-[color:var(--border-default)] bg-[color:var(--bg-base)] px-5 py-3 text-center text-xs font-bold uppercase tracking-widest text-[color:var(--text-primary)] transition hover:shadow-[4px_4px_0_var(--border-default)] hover:-translate-x-0.5 hover:-translate-y-0.5 focus-visible:outline-none focus-brutal"
                >
                  Load older messages
                </button>

                <div
                  data-role="dm-chat-messages"
                  id="dm-chat-messages"
                  phx-hook="DMChatScroller"
                  phx-update="stream"
                  data-peer={@selected_peer_ap_id || ""}
                  data-e2ee-peer-keys={Jason.encode!(@dm_peer_e2ee_keys)}
                  class="min-h-0 flex-1 space-y-4 overflow-y-auto bg-[color:var(--bg-subtle)] p-5"
                >
                  <div
                    id="dm-chat-empty"
                    class="hidden only:flex flex-col items-center justify-center gap-3 border-2 border-dashed border-[color:var(--border-muted)] bg-[color:var(--bg-base)] p-8 text-center"
                  >
                    <span class="inline-flex h-14 w-14 items-center justify-center border-2 border-[color:var(--border-default)] bg-[color:var(--bg-subtle)] text-2xl">
                      <.icon name="hero-chat-bubble-left-right" class="size-8" />
                    </span>
                    <p class="font-bold text-[color:var(--text-primary)]">No messages yet</p>
                    <p class="text-sm text-[color:var(--text-muted)]">
                      Start a conversation by sending an encrypted message below.
                    </p>
                  </div>

                  <div
                    :for={{id, message} <- @streams.chat_messages}
                    id={id}
                    data-role="dm-message"
                    data-kind={if message.actor == @current_user.ap_id, do: "sent", else: "received"}
                    class={[
                      "flex gap-3",
                      message.actor == @current_user.ap_id && "flex-row-reverse ml-auto"
                    ]}
                  >
                    <span class="mt-1 inline-flex h-8 w-8 shrink-0 items-center justify-center overflow-hidden border-2 border-[color:var(--border-default)] bg-[color:var(--bg-base)] text-xs font-bold">
                      <%= if message.actor == @current_user.ap_id do %>
                        <%= if avatar_url = avatar_src(@current_user.avatar_url, @current_user.ap_id) do %>
                          <img
                            src={avatar_url}
                            alt=""
                            class="h-full w-full object-cover"
                          />
                        <% else %>
                          {avatar_initial(@current_user.nickname)}
                        <% end %>
                      <% else %>
                        <%= if @selected_peer && @selected_peer.avatar_url do %>
                          <img
                            src={@selected_peer.avatar_url}
                            alt=""
                            class="h-full w-full object-cover"
                          />
                        <% else %>
                          {avatar_initial(@selected_peer && @selected_peer.display_name)}
                        <% end %>
                      <% end %>
                    </span>

                    <div class={[
                      "max-w-[75%] space-y-1",
                      message.actor == @current_user.ap_id && "items-end text-right"
                    ]}>
                      <div class={[
                        "border-2 border-[color:var(--border-default)] px-4 py-3 text-sm",
                        message.actor == @current_user.ap_id &&
                          "bg-[color:var(--text-primary)] text-[color:var(--bg-base)] [&_a]:!text-[#88aaff] dark:[&_a]:!text-[#0000ee] [&_a:hover]:!text-[#aaccff] dark:[&_a:hover]:!text-[#0000aa]",
                        message.actor != @current_user.ap_id &&
                          "bg-[color:var(--bg-base)] text-[color:var(--text-primary)] shadow-[3px_3px_0_var(--border-default)] [&_a]:!text-[#0000ee] dark:[&_a]:!text-[#88aaff] [&_a:hover]:!text-[#0000aa] dark:[&_a:hover]:!text-[#aaccff]"
                      ]}>
                        <.dm_message_body message={message} current_user={@current_user} />
                      </div>

                      <div class="flex items-center gap-2 font-mono text-[10px] font-bold uppercase tracking-widest text-[color:var(--text-muted)]">
                        <.icon
                          :if={encrypted_message?(message)}
                          name="hero-lock-closed"
                          class="size-3"
                        />
                        <span>{message_timestamp(message)}</span>
                      </div>
                    </div>
                  </div>
                </div>

                <div class="shrink-0 border-t-2 border-[color:var(--border-default)] bg-[color:var(--bg-base)] px-5 py-4">
                  <.form
                    for={@dm_form}
                    id="dm-form"
                    phx-change="dm_change"
                    phx-submit="send_dm"
                    phx-hook="E2EEDMComposer"
                    data-role="dm-composer"
                    data-user-ap-id={@current_user.ap_id}
                    data-peer-ap-id={@selected_peer_ap_id || ""}
                    class="space-y-3"
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

                    <input
                      type="hidden"
                      name="dm[encrypt]"
                      value={if @dm_peer_supports_e2ee?, do: "true", else: "false"}
                      data-role="dm-encrypt-enabled"
                    />

                    <p
                      data-role="dm-e2ee-feedback"
                      class="hidden border border-[color:var(--border-default)] bg-[color:var(--bg-subtle)] px-3 py-2 text-sm text-[color:var(--text-secondary)]"
                    >
                    </p>

                    <%= if @selected_peer do %>
                      <input
                        type="hidden"
                        name="dm[recipient]"
                        value={@dm_form.params["recipient"] || ""}
                        data-role="dm-recipient"
                      />
                    <% else %>
                      <div class="relative">
                        <input
                          type="text"
                          name="dm[recipient]"
                          value={@dm_form.params["recipient"] || ""}
                          data-role="dm-recipient"
                          placeholder="@alice or @alice@remote.example"
                          autocomplete="off"
                          phx-debounce="300"
                          class="w-full border-2 border-[color:var(--border-default)] bg-[color:var(--bg-base)] px-3 py-2 font-mono text-sm text-[color:var(--text-primary)] focus:outline-none focus-brutal placeholder:text-[color:var(--text-muted)]"
                        />

                        <div
                          :if={@recipient_suggestions != []}
                          data-role="dm-recipient-suggestions"
                          class="absolute left-0 right-0 z-30 mt-2 overflow-hidden border-2 border-[color:var(--border-default)] bg-[color:var(--bg-base)] shadow-[4px_4px_0_var(--border-default)] motion-safe:animate-rise"
                        >
                          <ul class="max-h-60 divide-y divide-[color:var(--border-muted)] overflow-y-auto">
                            <li :for={suggestion <- @recipient_suggestions}>
                              <button
                                type="button"
                                data-role="dm-recipient-suggestion"
                                data-handle={
                                  Map.get(suggestion, :handle) || Map.get(suggestion, "handle") || ""
                                }
                                phx-click="pick_recipient"
                                phx-value-ap_id={
                                  Map.get(suggestion, :ap_id) || Map.get(suggestion, "ap_id") || ""
                                }
                                phx-value-handle={
                                  Map.get(suggestion, :handle) || Map.get(suggestion, "handle") || ""
                                }
                                class="flex w-full items-center gap-3 px-4 py-3 text-left transition hover:bg-[color:var(--bg-subtle)] focus-visible:outline-none focus-brutal"
                              >
                                <span class="flex h-9 w-9 shrink-0 items-center justify-center overflow-hidden border-2 border-[color:var(--border-default)] bg-[color:var(--bg-subtle)] text-xs font-bold text-[color:var(--text-secondary)]">
                                  {avatar_initial(
                                    Map.get(suggestion, :display_name) ||
                                      Map.get(suggestion, "display_name") ||
                                      Map.get(suggestion, :handle) || Map.get(suggestion, "handle") ||
                                      "?"
                                  )}
                                </span>

                                <span class="min-w-0 flex-1">
                                  <span class="block truncate text-sm font-bold text-[color:var(--text-primary)]">
                                    {Map.get(suggestion, :display_name) ||
                                      Map.get(suggestion, "display_name") ||
                                      Map.get(suggestion, :handle) || Map.get(suggestion, "handle") ||
                                      ""}
                                  </span>
                                  <span class="mt-0.5 block truncate font-mono text-xs text-[color:var(--text-muted)]">
                                    {Map.get(suggestion, :handle) || Map.get(suggestion, "handle") ||
                                      ""}
                                  </span>
                                </span>
                              </button>
                            </li>
                          </ul>
                        </div>
                      </div>
                    <% end %>

                    <div class="flex gap-3">
                      <div class="relative h-[44px] flex-1">
                        <textarea
                          name="dm[content]"
                          rows="1"
                          placeholder="Type a message..."
                          class="absolute inset-0 resize-none border-2 border-[color:var(--border-default)] bg-[color:var(--bg-base)] px-3 py-2 pr-10 text-sm text-[color:var(--text-primary)] focus:outline-none focus-brutal placeholder:text-[color:var(--text-muted)]"
                        ><%= @dm_form.params["content"] || "" %></textarea>
                        <span
                          data-role="dm-composer-lock"
                          class="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 hidden text-[color:var(--success)]"
                        >
                          <.icon name="hero-lock-closed" class="size-4" />
                        </span>
                      </div>

                      <button
                        :if={@dm_peer_supports_e2ee?}
                        type="button"
                        data-role="dm-encrypt-toggle"
                        data-state="encrypted"
                        class={[
                          "inline-flex h-[44px] shrink-0 cursor-pointer items-center gap-2 border-2 border-[color:var(--border-default)] px-3 text-xs font-bold uppercase tracking-widest transition focus-visible:outline-none focus-brutal",
                          "data-[state=encrypted]:bg-[color:var(--success-subtle)] data-[state=encrypted]:text-[color:var(--success)] data-[state=encrypted]:hover:shadow-[3px_3px_0_var(--success)]",
                          "data-[state=plain]:bg-[color:var(--bg-subtle)] data-[state=plain]:text-[color:var(--text-muted)] data-[state=plain]:hover:shadow-[3px_3px_0_var(--border-default)]"
                        ]}
                      >
                        <span data-role="dm-encrypt-icon-encrypted">
                          <.icon name="hero-lock-closed" class="size-4" />
                        </span>
                        <span data-role="dm-encrypt-icon-plain" class="hidden">
                          <.icon name="hero-lock-open" class="size-4" />
                        </span>

                        <span data-role="dm-encrypt-label-encrypted">Encrypt</span>
                        <span data-role="dm-encrypt-label-plain" class="hidden">Plain</span>
                      </button>

                      <button
                        type="submit"
                        aria-label="Send message"
                        class="inline-flex h-[44px] w-[44px] shrink-0 cursor-pointer items-center justify-center border-2 border-[color:var(--border-default)] bg-[color:var(--text-primary)] text-[color:var(--bg-base)] transition hover:-translate-x-0.5 hover:-translate-y-0.5 hover:shadow-[4px_4px_0_var(--border-default)] focus-visible:outline-none focus-brutal"
                      >
                        <.icon name="hero-paper-airplane" class="size-5" />
                      </button>
                    </div>
                  </.form>
                </div>
              </main>
            </div>
          <% else %>
            <.card class="p-6">
              <p
                data-role="messages-auth-required"
                class="text-sm text-[color:var(--text-secondary)]"
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

  attr :message, :map, required: true
  attr :current_user, :any, default: nil

  defp dm_message_body(assigns) do
    is_own = assigns.message.actor == current_user_ap_id(assigns.current_user)
    assigns = assign(assigns, :is_own, is_own)

    ~H"""
    <% e2ee_payload = e2ee_payload_json(@message) %>
    <% current_user_ap_id = current_user_ap_id(@current_user) %>

    <div
      id={if is_binary(@message.id), do: "dm-message-body-#{@message.id}", else: Ecto.UUID.generate()}
      data-role="dm-message-body"
      data-e2ee-dm={e2ee_payload}
      data-current-user-ap-id={current_user_ap_id}
      phx-hook={if is_binary(e2ee_payload), do: "E2EEDMMessage", else: nil}
    >
      <%= if is_binary(e2ee_payload) do %>
        <span data-role="e2ee-dm-body">
          <span data-role="e2ee-dm-placeholder" class="italic opacity-60">[Encrypted]</span>
          <span
            data-role="e2ee-dm-decrypting"
            class="hidden ml-2 inline-flex items-center gap-1 italic opacity-60"
          >
            <span class="inline-flex animate-spin">
              <.icon name="hero-arrow-path" class="size-3" />
            </span>
            Decrypting…
          </span>
        </span>

        <span data-role="e2ee-dm-actions" class="ml-2">
          <button
            type="button"
            data-role="e2ee-dm-unlock"
            class={[
              "inline-flex cursor-pointer items-center gap-1 border px-2 py-0.5 align-middle font-mono text-[10px] font-bold uppercase tracking-wide transition focus-visible:outline-none",
              @is_own &&
                "border-[color:var(--bg-base)] text-[color:var(--bg-base)] hover:bg-[color:var(--bg-base)] hover:text-[color:var(--text-primary)]",
              !@is_own &&
                "border-[color:var(--border-default)] text-[color:var(--text-primary)] hover:bg-[color:var(--text-primary)] hover:text-[color:var(--bg-base)]"
            ]}
          >
            <.icon name="hero-lock-open" class="size-3" /> Unlock
          </button>
        </span>
      <% else %>
        {dm_content_html(@message)}
      <% end %>
    </div>
    """
  end

  defp conversations_page(user, seen_peers, opts \\ [])

  defp conversations_page(%User{} = user, %MapSet{} = seen_peers, opts) when is_list(opts) do
    messages =
      DirectMessages.list_for_user(user, Keyword.merge([limit: @conversations_page_size], opts))

    next_max_id =
      case List.last(messages) do
        %{id: id} when is_binary(id) -> id
        _ -> nil
      end

    conversations_has_more? =
      length(messages) == @conversations_page_size and is_binary(next_max_id)

    {conversations, seen_peers} =
      Enum.reduce(messages, {[], seen_peers}, fn message, {acc, seen_peers} ->
        peer_ap_id = peer_ap_id_for_dm(message, user.ap_id)

        if is_binary(peer_ap_id) and peer_ap_id != "" and
             not MapSet.member?(seen_peers, peer_ap_id) do
          peer = Actor.card(peer_ap_id)
          {[%{peer: peer, last_message: message} | acc], MapSet.put(seen_peers, peer_ap_id)}
        else
          {acc, seen_peers}
        end
      end)

    {Enum.reverse(conversations), seen_peers, next_max_id, conversations_has_more?}
  end

  defp conversations_page(_user, %MapSet{} = seen_peers, _opts), do: {[], seen_peers, nil, false}

  defp peer_ap_id_for_dm(%{actor: actor} = message, current_user_ap_id)
       when is_binary(actor) and is_binary(current_user_ap_id) do
    actor = String.trim(actor)

    cond do
      actor == "" ->
        nil

      actor == current_user_ap_id ->
        message
        |> dm_recipient_ap_ids()
        |> Enum.reject(&(&1 == current_user_ap_id))
        |> List.first()

      true ->
        actor
    end
  end

  defp peer_ap_id_for_dm(_message, _current_user_ap_id), do: nil

  defp dm_recipient_ap_ids(%{data: %{} = data}), do: dm_recipient_ap_ids(data)

  defp dm_recipient_ap_ids(%{} = data) do
    followers =
      data
      |> Map.get("actor")
      |> case do
        actor when is_binary(actor) and actor != "" -> actor <> "/followers"
        _ -> nil
      end

    @recipient_fields
    |> Enum.flat_map(fn field ->
      data
      |> Map.get(field, [])
      |> List.wrap()
      |> Enum.map(&extract_recipient_id/1)
    end)
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(fn value ->
      value == "" or value == @as_public or value == followers or
        String.ends_with?(value, "/followers")
    end)
    |> Enum.uniq()
  end

  defp dm_recipient_ap_ids(_data), do: []

  defp extract_recipient_id(%{"id" => id}) when is_binary(id), do: id
  defp extract_recipient_id(%{id: id}) when is_binary(id), do: id
  defp extract_recipient_id(id) when is_binary(id), do: id
  defp extract_recipient_id(_recipient), do: nil

  defp include_dm?(%{type: type} = note, %User{} = current_user)
       when type in ["Note", "EncryptedMessage"] do
    DirectMessages.direct?(note) and Objects.visible_to?(note, current_user)
  end

  defp include_dm?(_note, _current_user), do: false

  defp conversation_dom_id(%{peer: %{ap_id: ap_id}}) when is_binary(ap_id) do
    "dm-conversation-#{:erlang.phash2(ap_id)}"
  end

  defp conversation_dom_id(_conversation), do: Ecto.UUID.generate()

  defp message_dom_id(%{id: id}) when is_binary(id), do: "dm-message-#{id}"
  defp message_dom_id(_message), do: Ecto.UUID.generate()

  defp avatar_initial(name) when is_binary(name) do
    name = String.trim(name)

    case String.first(name) do
      nil -> "?"
      letter -> String.upcase(letter)
    end
  end

  defp avatar_initial(_), do: "?"

  defp dm_markers_for_conversations(%User{} = user, conversations) when is_list(conversations) do
    timelines =
      conversations
      |> Enum.map(fn
        %{peer: %{ap_id: ap_id}} -> dm_marker_timeline(ap_id)
        _ -> nil
      end)
      |> Enum.filter(&is_binary/1)

    user
    |> Markers.list_for_user(timelines)
    |> Enum.reduce(%{}, fn marker, acc ->
      Map.put(acc, marker.timeline, marker.last_read_id)
    end)
  end

  defp dm_markers_for_conversations(_user, _conversations), do: %{}

  defp dm_marker_timeline(peer_ap_id) when is_binary(peer_ap_id) do
    peer_ap_id = String.trim(peer_ap_id)

    if peer_ap_id == "" do
      nil
    else
      digest = :crypto.hash(:sha256, peer_ap_id)
      @dm_marker_prefix <> Base.url_encode64(digest, padding: false)
    end
  end

  defp dm_marker_timeline(_peer_ap_id), do: nil

  defp mark_dm_conversation_read(%User{} = user, peer_ap_id, last_message_id, dm_markers)
       when is_binary(peer_ap_id) and is_binary(last_message_id) and is_map(dm_markers) do
    timeline = dm_marker_timeline(peer_ap_id)
    last_read_id = last_message_id

    if is_binary(timeline) and timeline != "" do
      _ = Markers.upsert(user, timeline, last_read_id)
      Map.put(dm_markers, timeline, last_read_id)
    else
      dm_markers
    end
  end

  defp mark_dm_conversation_read(_user, _peer_ap_id, _last_message_id, dm_markers)
       when is_map(dm_markers),
       do: dm_markers

  defp mark_dm_conversation_read(_user, _peer_ap_id, _last_message_id, _dm_markers), do: %{}

  defp conversation_unread?(conversation, dm_markers, %User{ap_id: user_ap_id})
       when is_binary(user_ap_id) and is_map(dm_markers) do
    case conversation do
      %{peer: %{ap_id: peer_ap_id}, last_message: %{id: last_message_id, actor: actor}}
      when is_binary(peer_ap_id) and is_binary(last_message_id) and is_binary(actor) ->
        if actor == user_ap_id do
          false
        else
          timeline = dm_marker_timeline(peer_ap_id)
          last_read_id = if is_binary(timeline), do: Map.get(dm_markers, timeline), else: nil

          unread_id?(last_read_id, last_message_id)
        end

      _ ->
        false
    end
  end

  defp conversation_unread?(_conversation, _dm_markers, _current_user), do: false

  defp unread_id?(last_read_id, last_message_id)
       when is_binary(last_message_id) do
    with <<_::128>> = last_message_bin <- FlakeId.from_string(last_message_id) do
      case last_read_id do
        id when is_binary(id) ->
          case FlakeId.from_string(id) do
            <<_::128>> = last_read_bin -> last_read_bin < last_message_bin
            _ -> true
          end

        _ ->
          true
      end
    else
      _ -> false
    end
  end

  defp unread_id?(_last_read_id, _last_message_id), do: false

  defp dm_last_message_at(%{published: %DateTime{} = published}), do: published

  defp dm_last_message_at(%{inserted_at: %DateTime{} = inserted_at}), do: inserted_at

  defp dm_last_message_at(_message), do: nil

  defp e2ee_payload_json(%{data: %{} = data}) do
    case Map.get(data, "egregoros:e2ee_dm") do
      %{} = payload when map_size(payload) > 0 -> Jason.encode!(payload)
      _ -> nil
    end
  end

  defp e2ee_payload_json(_message), do: nil

  defp encrypted_message?(%{data: %{} = data}) do
    case Map.get(data, "egregoros:e2ee_dm") do
      %{} = payload -> map_size(payload) > 0
      _ -> false
    end
  end

  defp encrypted_message?(_message), do: false

  defp current_user_ap_id(%{ap_id: ap_id}) when is_binary(ap_id), do: ap_id
  defp current_user_ap_id(_current_user), do: ""

  defp dm_content_html(%{data: %{} = data} = object) do
    raw = Map.get(data, "content", "")
    emojis = CustomEmojis.from_object(object)
    ap_tags = Map.get(data, "tag", [])

    raw
    |> HTML.to_safe_html(format: :html, emojis: emojis, ap_tags: ap_tags)
    |> Phoenix.HTML.raw()
  end

  defp dm_content_html(_message), do: ""

  defp dm_preview_text(%{data: %{} = data} = message, %User{} = current_user) do
    if encrypted_message?(message) do
      "Encrypted message"
    else
      raw = data |> Map.get("content", "") |> to_string()

      text =
        raw
        |> FastSanitize.strip_tags()
        |> case do
          {:ok, text} -> text
          _ -> ""
        end
        |> String.replace(~r/\s+/, " ")
        |> String.trim()
        |> strip_leading_self_mention(current_user)

      text =
        if String.starts_with?(text, "Encrypted message"), do: "Encrypted message", else: text

      cond do
        text == "" -> "—"
        String.length(text) <= 80 -> text
        true -> String.slice(text, 0, 77) <> "..."
      end
    end
  end

  defp dm_preview_text(_message, _current_user), do: "—"

  defp strip_leading_self_mention(text, %User{nickname: nickname})
       when is_binary(text) and is_binary(nickname) and nickname != "" do
    pattern = ~r/^@#{Regex.escape(nickname)}(?:@[^\s]+)?[,:]?\s+/u
    Regex.replace(pattern, text, "")
  end

  defp strip_leading_self_mention(text, _current_user) when is_binary(text), do: text

  defp strip_leading_self_mention(_text, _current_user), do: ""

  defp message_timestamp(%{published: %DateTime{} = published}) do
    published
    |> DateTime.to_time()
    |> Time.truncate(:second)
    |> Time.to_string()
  end

  defp message_timestamp(_message), do: "now"

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

  defp avatar_src(avatar_url, base) when is_binary(avatar_url) and is_binary(base) do
    avatar_url =
      avatar_url
      |> URL.absolute(base)
      |> to_string()
      |> String.trim()

    if avatar_url == "", do: nil, else: avatar_url
  end

  defp avatar_src(avatar_url, _base) when is_binary(avatar_url) do
    avatar_url =
      avatar_url
      |> URL.absolute()
      |> to_string()
      |> String.trim()

    if avatar_url == "", do: nil, else: avatar_url
  end

  defp avatar_src(_avatar_url, _base), do: nil

  defp notifications_count(nil), do: 0

  defp notifications_count(%User{} = user) do
    user
    |> Notifications.list_for_user(limit: 20, include_offers?: true)
    |> length()
  end
end
