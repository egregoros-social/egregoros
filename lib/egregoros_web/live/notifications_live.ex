defmodule EgregorosWeb.NotificationsLive do
  use EgregorosWeb, :live_view

  alias Egregoros.Activities.Accept
  alias Egregoros.Activities.Offer
  alias Egregoros.Activities.Reject
  alias Egregoros.CustomEmojis
  alias Egregoros.EmojiReactions
  alias Egregoros.HTML
  alias Egregoros.Notifications
  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Relationships
  alias Egregoros.User
  alias Egregoros.Users
  alias EgregorosWeb.Components.NotificationItems.FollowRequestNotification
  alias EgregorosWeb.Components.NotificationItems.NotificationItem
  alias EgregorosWeb.ProfilePaths
  alias EgregorosWeb.URL
  alias EgregorosWeb.ViewModels.Actor, as: ActorVM

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
    follow_requests = list_follow_requests(current_user, limit: @page_size)

    {:ok,
     socket
     |> assign(
       current_user: current_user,
       notifications_count: notifications_count(current_user),
       notifications_filter: "all",
       notifications_cursor: notifications_cursor(notifications),
       notifications_end?: length(notifications) < @page_size,
       follow_requests: decorate_follow_requests(follow_requests)
     )
     |> stream(:notifications, decorate_notifications(notifications, current_user),
       dom_id: &notification_dom_id/1
     )}
  end

  @impl true
  def handle_info({:notification_created, activity}, socket) do
    case socket.assigns.current_user do
      %User{} ->
        entry = decorate_notification(activity, socket.assigns.current_user)

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
              Enum.reduce(
                decorate_notifications(notifications, socket.assigns.current_user),
                socket,
                fn entry, socket ->
                  stream_insert(socket, :notifications, entry, at: -1)
                end
              )

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

    if filter in ~w(all follows requests likes reposts mentions reactions badges) do
      {:noreply, assign(socket, notifications_filter: filter)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("follow_request_accept", %{"id" => id}, socket) do
    relationship_id = id |> to_string() |> String.trim()

    with %User{} = current_user <- socket.assigns.current_user,
         true <- flake_id?(relationship_id),
         %{type: "FollowRequest", object: object_ap_id, activity_ap_id: follow_ap_id} <-
           Relationships.get(relationship_id),
         true <- object_ap_id == current_user.ap_id,
         follow_ap_id when is_binary(follow_ap_id) and follow_ap_id != "" <- follow_ap_id,
         %Object{type: "Follow"} = follow_object <- Objects.get_by_ap_id(follow_ap_id),
         {:ok, _accept_object} <-
           Pipeline.ingest(Accept.build(current_user, follow_object), local: true) do
      {:noreply,
       socket
       |> put_flash(:info, "Follow request accepted.")
       |> assign(
         follow_requests:
           decorate_follow_requests(list_follow_requests(current_user, limit: @page_size))
       )}
    else
      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("follow_request_reject", %{"id" => id}, socket) do
    relationship_id = id |> to_string() |> String.trim()

    with %User{} = current_user <- socket.assigns.current_user,
         true <- flake_id?(relationship_id),
         %{type: "FollowRequest", object: object_ap_id, activity_ap_id: follow_ap_id} <-
           Relationships.get(relationship_id),
         true <- object_ap_id == current_user.ap_id,
         follow_ap_id when is_binary(follow_ap_id) and follow_ap_id != "" <- follow_ap_id,
         %Object{type: "Follow"} = follow_object <- Objects.get_by_ap_id(follow_ap_id),
         {:ok, _reject_object} <-
           Pipeline.ingest(Reject.build(current_user, follow_object), local: true) do
      {:noreply,
       socket
       |> put_flash(:info, "Follow request rejected.")
       |> assign(
         follow_requests:
           decorate_follow_requests(list_follow_requests(current_user, limit: @page_size))
       )}
    else
      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("offer_accept", %{"id" => id}, socket) do
    offer_id = id |> to_string() |> String.trim()

    with %User{} = current_user <- socket.assigns.current_user,
         %Object{type: "Offer"} = offer_object <- fetch_offer(offer_id),
         true <- offer_addressed_to_user?(offer_object, current_user),
         {:ok, _accept_object} <-
           Pipeline.ingest(Accept.build(current_user, offer_object), local: true) do
      entry = decorate_notification(offer_object, current_user)

      {:noreply,
       socket
       |> stream_insert(:notifications, entry)
       |> put_flash(:info, "Badge accepted.")}
    else
      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("offer_reject", %{"id" => id}, socket) do
    offer_id = id |> to_string() |> String.trim()

    with %User{} = current_user <- socket.assigns.current_user,
         %Object{type: "Offer"} = offer_object <- fetch_offer(offer_id),
         true <- offer_addressed_to_user?(offer_object, current_user),
         {:ok, _reject_object} <-
           Pipeline.ingest(Reject.build(current_user, offer_object), local: true) do
      entry = decorate_notification(offer_object, current_user)

      {:noreply,
       socket
       |> stream_insert(:notifications, entry)
       |> put_flash(:info, "Badge rejected.")}
    else
      _ ->
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
                <p class="text-xs font-bold uppercase tracking-wide text-[color:var(--text-muted)]">
                  Notifications
                </p>
                <h2 class="mt-2 text-2xl font-bold text-[color:var(--text-primary)]">
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
                filter="requests"
                current={@notifications_filter}
                label="Requests"
                icon="hero-user-circle"
              />
              <.filter_button
                filter="badges"
                current={@notifications_filter}
                label="Badges"
                icon="hero-trophy"
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
              <.filter_button
                filter="mentions"
                current={@notifications_filter}
                label="Mentions"
                icon="hero-at-symbol"
              />
              <.filter_button
                filter="reactions"
                current={@notifications_filter}
                label="Reactions"
                icon="hero-face-smile"
              />
            </div>
          </.card>

          <%= if @current_user do %>
            <div
              id="notifications-list"
              data-role="notifications-list"
              data-filter={@notifications_filter}
              class="space-y-4"
            >
              <div data-role="follow-requests" class="space-y-4">
                <div
                  id="follow-requests-empty"
                  class="hidden only:block border-2 border-[color:var(--border-default)] bg-[color:var(--bg-subtle)] p-6 text-sm text-[color:var(--text-secondary)]"
                >
                  No follow requests yet.
                </div>

                <FollowRequestNotification.follow_request_notification
                  :for={entry <- @follow_requests}
                  id={"follow-request-#{entry.relationship.id}"}
                  entry={entry}
                />
              </div>

              <div
                id="notifications-stream"
                data-role="notifications-stream"
                phx-update="stream"
                class="space-y-4"
              >
                <div
                  id="notifications-empty"
                  class="hidden only:block border-2 border-[color:var(--border-default)] bg-[color:var(--bg-subtle)] p-6 text-sm text-[color:var(--text-secondary)]"
                >
                  No notifications yet.
                </div>

                <NotificationItem.notification_item
                  :for={{id, entry} <- @streams.notifications}
                  id={id}
                  entry={entry}
                />
              </div>
            </div>

            <div :if={!@notifications_end?} class="flex justify-center py-2">
              <.button
                data-role="notifications-load-more"
                phx-click={JS.show(to: "#notifications-loading-more") |> JS.push("load_more")}
                phx-disable-with="Loading..."
                aria-label="Load more notifications"
                variant="secondary"
              >
                <.icon name="hero-chevron-down" class="size-4" /> Load more
              </.button>
            </div>

            <div
              :if={!@notifications_end?}
              id="notifications-loading-more"
              data-role="notifications-loading-more"
              class="hidden space-y-4"
              aria-hidden="true"
            >
              <.skeleton_status_card
                :for={_ <- 1..2}
                class="border-2 border-[color:var(--border-default)]"
              />
            </div>
          <% else %>
            <.card class="p-6">
              <p
                data-role="notifications-auth-required"
                class="text-sm text-[color:var(--text-secondary)]"
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
      data-active={if @active?, do: "true", else: "false"}
      phx-click={set_filter_js(@filter)}
      aria-pressed={@active?}
      class={[
        "inline-flex items-center gap-2 border-2 px-4 py-2 text-xs font-bold uppercase tracking-wide transition",
        "data-[active=true]:border-[color:var(--border-default)] data-[active=true]:bg-[color:var(--text-primary)] data-[active=true]:text-[color:var(--bg-base)]",
        "data-[active=false]:border-[color:var(--border-default)] data-[active=false]:bg-[color:var(--bg-base)] data-[active=false]:text-[color:var(--text-secondary)] data-[active=false]:hover:bg-[color:var(--text-primary)] data-[active=false]:hover:text-[color:var(--bg-base)]"
      ]}
    >
      <.icon name={@icon} class="size-4" />
      {@label}
    </button>
    """
  end

  defp set_filter_js(filter) when is_binary(filter) do
    JS.set_attribute({"data-filter", filter}, to: "#notifications-list")
    |> JS.set_attribute({"aria-pressed", "false"}, to: "button[data-role='notifications-filter']")
    |> JS.set_attribute({"data-active", "false"}, to: "button[data-role='notifications-filter']")
    |> JS.set_attribute({"aria-pressed", "true"},
      to: "button[data-role='notifications-filter'][data-filter='#{filter}']"
    )
    |> JS.set_attribute({"data-active", "true"},
      to: "button[data-role='notifications-filter'][data-filter='#{filter}']"
    )
    |> JS.push("set_notifications_filter", value: %{filter: filter})
  end

  defp list_notifications(nil, _opts), do: []

  defp list_notifications(%User{} = user, opts) when is_list(opts) do
    Notifications.list_for_user(user, Keyword.put(opts, :include_offers?, true))
  end

  defp list_follow_requests(nil, _opts), do: []

  defp list_follow_requests(%User{} = user, opts) when is_list(opts) do
    limit =
      opts
      |> Keyword.get(:limit, @page_size)
      |> max(1)
      |> min(80)

    Relationships.list_by_type_object("FollowRequest", user.ap_id, limit)
  end

  defp decorate_notifications(notifications, current_user) when is_list(notifications) do
    Enum.map(notifications, &decorate_notification(&1, current_user))
  end

  defp decorate_follow_requests(relationships) when is_list(relationships) do
    Enum.map(relationships, fn relationship ->
      %{
        relationship: relationship,
        actor: ActorVM.card(relationship.actor)
      }
    end)
  end

  defp decorate_notification(%{type: type} = notification, current_user)
       when is_binary(type) do
    actor = ActorVM.card(notification.actor)

    note =
      case type do
        "Like" -> note_for_ap_id(notification.object)
        "Announce" -> note_for_ap_id(notification.object)
        "EmojiReact" -> note_for_ap_id(notification.object)
        "Note" -> note_for_ap_id(notification.ap_id)
        _ -> nil
      end

    target_path = status_path_for_note(note)
    preview_html = note_preview(note)
    preview_text = note_preview_text(note)

    {icon, message, message_emojis, reaction_emoji} =
      case type do
        "Follow" ->
          {"hero-user-plus", "#{actor.display_name} followed you", actor.emojis, nil}

        "Like" ->
          msg =
            if preview_text do
              "#{actor.display_name} liked \"#{preview_text}\""
            else
              "#{actor.display_name} liked your post"
            end

          {"hero-heart", msg, actor.emojis, nil}

        "Announce" ->
          {"hero-arrow-path", "#{actor.display_name} reposted your post", actor.emojis, nil}

        "EmojiReact" ->
          emoji_raw =
            notification.data
            |> Map.get("content")
            |> to_string()
            |> String.trim()

          emoji = EmojiReactions.normalize_content(emoji_raw) |> to_string() |> String.trim()

          emoji_url =
            EmojiReactions.find_custom_emoji_url(
              emoji,
              Map.get(notification.data, "tag")
            )

          {emoji_token, reaction_emojis, reaction_display} =
            cond do
              is_binary(emoji_url) and emoji_url != "" and emoji != "" ->
                {":#{emoji}:", [%{shortcode: emoji, url: emoji_url}],
                 %{type: :custom, shortcode: emoji, url: emoji_url}}

              emoji_raw != "" ->
                {emoji_raw, [], %{type: :unicode, emoji: emoji_raw}}

              true ->
                {"", [], nil}
            end

          message =
            cond do
              preview_text && emoji_token != "" ->
                "#{actor.display_name} reacted #{emoji_token} to \"#{preview_text}\""

              preview_text ->
                "#{actor.display_name} reacted to \"#{preview_text}\""

              emoji_token != "" ->
                "#{actor.display_name} reacted #{emoji_token} to your post"

              true ->
                "#{actor.display_name} reacted to your post"
            end

          message_emojis = merge_emojis(actor.emojis, reaction_emojis)

          {"hero-face-smile", message, message_emojis, reaction_display}

        "Offer" ->
          offer_label =
            case actor.ap_id do
              ap_id when is_binary(ap_id) and ap_id != "" -> ap_id
              _ -> actor.display_name
            end

          {"hero-gift", "#{offer_label} offered you a badge", actor.emojis, nil}

        "Note" ->
          {"hero-at-symbol", "#{actor.display_name} mentioned you", actor.emojis, nil}

        _ ->
          {"hero-bell", "#{actor.display_name} sent activity", actor.emojis, nil}
      end

    {offer_title, offer_description} = offer_details(notification)
    offer_image_url = offer_image_url(notification)
    offer_badge_path = offer_badge_path(notification, current_user)
    offer_response = offer_response(notification, current_user)

    %{
      notification: notification,
      type: type,
      actor: actor,
      icon: icon,
      message: message,
      message_emojis: message_emojis,
      preview_html: preview_html,
      preview_text: preview_text,
      target_path: target_path,
      reaction_emoji: reaction_emoji,
      offer_title: offer_title,
      offer_description: offer_description,
      offer_image_url: offer_image_url,
      offer_badge_path: offer_badge_path,
      offer_response: offer_response
    }
  end

  defp note_preview(%Object{type: "Note"} = object) do
    raw = object.data |> Map.get("content", "") |> to_string()
    emojis = CustomEmojis.from_object(object)
    ap_tags = Map.get(object.data, "tag", [])

    raw
    |> HTML.to_safe_html(format: :html, emojis: emojis, ap_tags: ap_tags)
    |> Phoenix.HTML.raw()
  end

  defp note_preview(_note), do: nil

  # Returns a short plain text preview of the note content (max 30 chars)
  defp note_preview_text(%Object{type: "Note"} = object) do
    raw = object.data |> Map.get("content", "") |> to_string()

    text =
      raw
      |> FastSanitize.strip_tags()
      |> case do
        {:ok, text} -> text
        _ -> ""
      end
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    case text do
      "" -> nil
      text when byte_size(text) <= 30 -> text
      text -> String.slice(text, 0, 27) <> "..."
    end
  end

  defp note_preview_text(_note), do: nil

  defp note_for_ap_id(ap_id) when is_binary(ap_id) do
    case Objects.get_by_ap_id(ap_id) do
      %Object{type: "Note"} = note -> note
      _ -> nil
    end
  end

  defp note_for_ap_id(_ap_id), do: nil

  defp offer_details(%Object{type: "Offer"} = offer) do
    achievement =
      offer
      |> offer_credential()
      |> credential_subject()
      |> credential_achievement()

    {
      achievement_field(achievement, "name"),
      achievement_field(achievement, "description")
    }
  end

  defp offer_details(_notification), do: {nil, nil}

  defp offer_image_url(%Object{type: "Offer"} = offer) do
    offer
    |> offer_credential()
    |> credential_subject()
    |> credential_achievement()
    |> achievement_image()
    |> absolute_image_url()
  end

  defp offer_image_url(_notification), do: nil

  defp offer_credential(%Object{type: "Offer"} = offer) do
    case offer.data do
      %{"object" => %{} = embedded} -> embedded
      _ -> credential_from_ap_id(offer.object)
    end
  end

  defp offer_credential(_offer), do: nil

  defp offer_badge_path(%Object{type: "Offer"} = offer, %User{} = user) do
    offer_ap_id =
      case offer.ap_id do
        ap_id when is_binary(ap_id) -> String.trim(ap_id)
        _ -> ""
      end

    with true <- offer_ap_id != "",
         %Object{id: accept_id} <-
           Objects.get_by_type_actor_object("Accept", user.ap_id, offer_ap_id),
         badge_id <- accept_id |> to_string() |> String.trim(),
         true <- badge_id != "",
         path when is_binary(path) <- badge_path(user, badge_id) do
      path
    else
      _ -> nil
    end
  end

  defp offer_badge_path(_offer, _user), do: nil

  defp offer_response(%Object{type: "Offer"} = offer, %User{} = user) do
    offer_ap_id =
      case offer.ap_id do
        ap_id when is_binary(ap_id) -> String.trim(ap_id)
        _ -> ""
      end

    cond do
      offer_ap_id == "" ->
        nil

      Relationships.get_by_type_actor_object("OfferAccepted", user.ap_id, offer_ap_id) ->
        "You accepted this badge."

      Relationships.get_by_type_actor_object("OfferRejected", user.ap_id, offer_ap_id) ->
        "You rejected this badge."

      true ->
        nil
    end
  end

  defp offer_response(_offer, _user), do: nil

  defp badge_path(%User{} = user, badge_id) when is_binary(badge_id) do
    case ProfilePaths.profile_path(user) do
      path when is_binary(path) and path != "" -> path <> "/badges/" <> badge_id
      _ -> nil
    end
  end

  defp badge_path(_user, _badge_id), do: nil

  defp credential_from_ap_id(credential_ap_id) when is_binary(credential_ap_id) do
    case Objects.get_by_ap_id(credential_ap_id) do
      %Object{data: %{} = data} -> data
      _ -> nil
    end
  end

  defp credential_from_ap_id(_credential_ap_id), do: nil

  defp credential_subject(%{} = credential) do
    credential
    |> Map.get("credentialSubject")
    |> List.wrap()
    |> Enum.find(&is_map/1)
  end

  defp credential_subject(_credential), do: nil

  defp credential_achievement(%{} = subject) do
    Map.get(subject, "achievement") || Map.get(subject, :achievement)
  end

  defp credential_achievement(_subject), do: nil

  defp achievement_field(%{} = achievement, "name") do
    Map.get(achievement, "name") || Map.get(achievement, :name)
  end

  defp achievement_field(%{} = achievement, "description") do
    Map.get(achievement, "description") || Map.get(achievement, :description)
  end

  defp achievement_field(_achievement, _field), do: nil

  defp achievement_image(%{} = achievement) do
    Map.get(achievement, "image") || Map.get(achievement, :image)
  end

  defp achievement_image(_achievement), do: nil

  defp absolute_image_url(nil), do: nil

  defp absolute_image_url(url) when is_binary(url) do
    URL.absolute(url)
  end

  defp absolute_image_url(%{"id" => id}) when is_binary(id), do: absolute_image_url(id)
  defp absolute_image_url(%{"url" => url}) when is_binary(url), do: absolute_image_url(url)
  defp absolute_image_url(%{id: id}) when is_binary(id), do: absolute_image_url(id)
  defp absolute_image_url(%{url: url}) when is_binary(url), do: absolute_image_url(url)
  defp absolute_image_url(_image), do: nil

  defp fetch_offer(offer_id) when is_binary(offer_id) do
    offer_id = String.trim(offer_id)

    cond do
      offer_id == "" ->
        nil

      true ->
        Objects.get(offer_id) || Objects.get_by_ap_id(offer_id)
    end
  end

  defp fetch_offer(_offer_id), do: nil

  defp offer_addressed_to_user?(%Object{} = offer_object, %User{} = user) do
    user.ap_id in Offer.recipient_ap_ids(offer_object)
  end

  defp offer_addressed_to_user?(_offer_object, _user), do: false

  defp status_path_for_note(%Object{} = note) do
    actor = ActorVM.card(note.actor)

    cond do
      note.local == true ->
        with uuid when is_binary(uuid) and uuid != "" <- URL.local_object_uuid(note.ap_id),
             "/@" <> _rest = profile_path <- ProfilePaths.profile_path(actor.handle) do
          profile_path <> "/" <> uuid
        else
          _ -> nil
        end

      is_binary(note.id) ->
        with "/@" <> _rest = profile_path <- ProfilePaths.profile_path(actor.handle) do
          profile_path <> "/" <> note.id
        else
          _ -> nil
        end

      true ->
        nil
    end
  end

  defp status_path_for_note(_note), do: nil

  defp merge_emojis(list_a, list_b) when is_list(list_a) and is_list(list_b) do
    (list_a ++ list_b)
    |> Enum.filter(&is_map/1)
    |> Enum.uniq_by(fn
      %{shortcode: shortcode} when is_binary(shortcode) -> shortcode
      %{"shortcode" => shortcode} when is_binary(shortcode) -> shortcode
      other -> other
    end)
  end

  defp merge_emojis(list_a, list_b), do: merge_emojis(List.wrap(list_a), List.wrap(list_b))

  defp notifications_count(nil), do: 0

  defp notifications_count(%User{} = user) do
    user
    |> Notifications.list_for_user(limit: @page_size, include_offers?: true)
    |> length()
  end

  defp notifications_cursor([]), do: nil

  defp notifications_cursor(notifications) when is_list(notifications) do
    case List.last(notifications) do
      %{id: id} when is_binary(id) -> id
      _ -> nil
    end
  end

  defp notification_dom_id(%{notification: %{id: id}}) when is_binary(id),
    do: "notification-#{id}"

  defp notification_dom_id(_notification), do: Ecto.UUID.generate()

  defp flake_id?(id) when is_binary(id) do
    id = String.trim(id)
    byte_size(id) == 18 and FlakeId.flake_id?(id)
  end

  defp flake_id?(_id), do: false
end
