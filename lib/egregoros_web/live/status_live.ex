defmodule EgregorosWeb.StatusLive do
  use EgregorosWeb, :live_view

  alias Egregoros.Mentions
  alias Egregoros.Domain
  alias Egregoros.Federation.ThreadDiscovery
  alias Egregoros.Workers.RefreshPoll
  alias Egregoros.Badges
  alias Egregoros.Interactions
  alias Egregoros.Media
  alias Egregoros.MediaStorage
  alias Egregoros.Notifications
  alias Egregoros.Objects
  alias Egregoros.Publish
  alias Egregoros.Timeline
  alias Egregoros.User
  alias Egregoros.Users
  alias EgregorosWeb.Endpoint
  alias EgregorosWeb.MentionAutocomplete
  alias EgregorosWeb.Param
  alias EgregorosWeb.ProfilePaths
  alias EgregorosWeb.ViewModels.Actor, as: ActorVM
  alias EgregorosWeb.ViewModels.Status, as: StatusVM

  @reply_max_chars 5000
  @thread_replies_refresh_after_seconds 300
  @thread_retry_delay_ms 4_000

  @impl true
  def mount(%{"nickname" => nickname, "uuid" => uuid} = params, session, socket) do
    current_user =
      case Map.get(session, "user_id") do
        nil -> nil
        id -> Users.get(id)
      end

    back_timeline = back_timeline_from_params(params, current_user)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Egregoros.PubSub, Timeline.public_topic())

      if match?(%User{}, current_user) do
        Phoenix.PubSub.subscribe(Egregoros.PubSub, Timeline.user_topic(current_user.ap_id))
      end
    end

    object =
      case object_for_uuid_param(uuid) do
        %Egregoros.Object{} = object ->
          if Objects.visible_to?(object, current_user), do: object, else: nil

        _ ->
          nil
      end

    prefill_reply? = Param.truthy?(Map.get(params, "reply")) and not is_nil(current_user)

    current_user_handle =
      case current_user do
        %User{} = user -> ActorVM.handle(user, user.ap_id)
        _ -> nil
      end

    {status_entry, ancestor_entries, descendant_entries, thread_note, missing_parent?} =
      case object do
        %{type: "Note"} = note ->
          status_entry = StatusVM.decorate(note, current_user)

          raw_ancestors = Objects.thread_ancestors(note)

          ancestors =
            raw_ancestors
            |> Enum.filter(&Objects.visible_to?(&1, current_user))
            |> StatusVM.decorate_many(current_user)

          descendants = decorate_descendants(note, current_user)

          parent_ap_id =
            note.data
            |> Map.get("inReplyTo")
            |> in_reply_to_ap_id()
            |> normalize_binary()

          missing_parent? = parent_ap_id != "" and raw_ancestors == []

          {status_entry, ancestors, descendants, note, missing_parent?}

        %{type: "Question"} = question ->
          # Questions (polls) don't have thread context in the same way Notes do
          status_entry = StatusVM.decorate(question, current_user)
          {status_entry, [], [], question, false}

        _ ->
          {nil, [], [], nil, false}
      end

    fetching_replies? =
      case thread_note do
        %Egregoros.Object{type: "Note", local: false} = note ->
          replies_url = note |> replies_url() |> normalize_binary()

          if replies_url == "" do
            false
          else
            if connected?(socket) do
              _ =
                ThreadDiscovery.enqueue_replies(note,
                  refresh_after_seconds: @thread_replies_refresh_after_seconds
                )
            end

            descendant_entries == [] and is_nil(note.thread_replies_checked_at)
          end

        _ ->
          false
      end

    if connected?(socket) and missing_parent? do
      _ = ThreadDiscovery.enqueue(thread_note)
      _ = schedule_thread_retry(:context)
    end

    if connected?(socket) and fetching_replies? do
      _ = schedule_thread_retry(:replies)
    end

    # Schedule poll refresh for remote Questions
    if connected?(socket) and
         match?(%Egregoros.Object{type: "Question", local: false}, thread_note) do
      _ = RefreshPoll.maybe_enqueue(thread_note)
    end

    reply_to_handle =
      if prefill_reply? and status_entry do
        status_entry.actor.handle
      else
        nil
      end

    reply_to_ap_id =
      if prefill_reply? and status_entry do
        status_entry.object.ap_id
      else
        nil
      end

    reply_prefill_mention_handles =
      if prefill_reply? and status_entry do
        mention_handle_names(status_entry.object)
      else
        []
      end

    reply_params =
      if is_binary(reply_to_ap_id) do
        default_reply_params() |> Map.put("in_reply_to", reply_to_ap_id)
      else
        default_reply_params()
      end

    reply_form = Phoenix.Component.to_form(reply_params, as: :reply)

    thread_index = build_thread_index(status_entry, ancestor_entries, descendant_entries)

    socket =
      socket
      |> assign(
        current_user: current_user,
        current_user_handle: current_user_handle,
        notifications_count: notifications_count(current_user),
        nickname: nickname,
        uuid: uuid,
        back_timeline: back_timeline,
        status: status_entry,
        ancestors: ancestor_entries,
        descendants: descendant_entries,
        thread_index: thread_index,
        thread_missing_context?: missing_parent?,
        thread_fetching_replies?: fetching_replies?,
        thread_context_retry_visible?: false,
        thread_replies_retry_visible?: false,
        reply_to_ap_id: reply_to_ap_id,
        reply_to_handle: reply_to_handle,
        reply_prefill_mention_handles: reply_prefill_mention_handles,
        reply_form: reply_form,
        reply_media_alt: %{},
        reply_options_open?: false,
        reply_cw_open?: false,
        mention_suggestions: %{}
      )
      |> allow_upload(:reply_media,
        accept: ~w(
          .png
          .jpg
          .jpeg
          .webp
          .gif
          .heic
          .heif
          .mp4
          .webm
          .mov
          .m4a
          .mp3
          .ogg
          .opus
          .wav
          .aac
        ),
        max_entries: 4,
        max_file_size: 10_000_000,
        auto_upload: true
      )
      |> maybe_redirect_to_canonical_permalink(params)

    {:ok, socket}
  end

  @impl true
  def handle_info({:post_created, %Egregoros.Object{} = object}, socket) do
    socket =
      if thread_relevant?(socket, object) do
        refresh_thread(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:post_updated, %Egregoros.Object{} = object}, socket) do
    socket =
      if thread_relevant?(socket, object) do
        refresh_thread(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:thread_retry_available, :context}, socket) do
    socket =
      if socket.assigns.thread_missing_context? do
        assign(socket, thread_context_retry_visible?: true)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:thread_retry_available, :replies}, socket) do
    socket =
      if socket.assigns.thread_fetching_replies? do
        assign(socket, thread_replies_retry_visible?: true)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info(_message, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("copied_link", _params, socket) do
    {:noreply, put_flash(socket, :info, "Copied link to clipboard.")}
  end

  def handle_event("fetch_thread_context", _params, socket) do
    case socket.assigns do
      %{status: %{object: %{type: "Note"} = note}} ->
        _ = ThreadDiscovery.enqueue(note)
        {:noreply, put_flash(socket, :info, "Queued a context fetch.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("fetch_thread_replies", _params, socket) do
    case socket.assigns do
      %{status: %{object: %{type: "Note"} = note}} ->
        _ = ThreadDiscovery.enqueue_replies(note, force: true)
        {:noreply, put_flash(socket, :info, "Queued a replies fetch.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("mention_search", %{"q" => q, "scope" => scope}, socket) do
    q = q |> to_string() |> String.trim() |> String.trim_leading("@")
    scope = scope |> to_string() |> String.trim()

    suggestions =
      if q == "" or scope == "" do
        []
      else
        MentionAutocomplete.suggestions(q, limit: 8, current_user: socket.assigns.current_user)
      end

    mention_suggestions =
      socket.assigns.mention_suggestions
      |> Map.put(scope, suggestions)

    {:noreply, assign(socket, mention_suggestions: mention_suggestions)}
  end

  def handle_event("mention_clear", %{"scope" => scope}, socket) do
    scope = scope |> to_string() |> String.trim()

    mention_suggestions =
      socket.assigns.mention_suggestions
      |> Map.delete(scope)

    {:noreply, assign(socket, mention_suggestions: mention_suggestions)}
  end

  def handle_event("cancel_reply_media", %{"ref" => ref}, socket) do
    {:noreply,
     socket
     |> cancel_upload(:reply_media, ref)
     |> assign(:reply_media_alt, Map.delete(socket.assigns.reply_media_alt, ref))}
  end

  def handle_event("toggle_like", %{"id" => id}, socket) do
    post_id = id |> to_string() |> String.trim()

    with %User{} = user <- socket.assigns.current_user,
         true <- flake_id?(post_id) do
      _ = Interactions.toggle_like(user, post_id)

      {:noreply, refresh_thread(socket)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to like posts.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_repost", %{"id" => id}, socket) do
    post_id = id |> to_string() |> String.trim()

    with %User{} = user <- socket.assigns.current_user,
         true <- flake_id?(post_id) do
      result = Interactions.toggle_repost(user, post_id)

      socket =
        case result do
          {:ok, _} ->
            case Badges.badge_share_flash_message(user, post_id) do
              message when is_binary(message) and message != "" ->
                put_flash(socket, :info, message)

              _ ->
                socket
            end

          _ ->
            socket
        end

      {:noreply, refresh_thread(socket)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to repost.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_reaction", %{"id" => id, "emoji" => emoji}, socket) do
    post_id = id |> to_string() |> String.trim()

    with %User{} = user <- socket.assigns.current_user,
         true <- flake_id?(post_id) do
      emoji = to_string(emoji)
      _ = Interactions.toggle_reaction(user, post_id, emoji)

      {:noreply, refresh_thread(socket)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to react.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_bookmark", %{"id" => id}, socket) do
    post_id = id |> to_string() |> String.trim()

    with %User{} = user <- socket.assigns.current_user,
         true <- flake_id?(post_id) do
      _ = Interactions.toggle_bookmark(user, post_id)

      {:noreply, refresh_thread(socket)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to bookmark posts.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("vote_on_poll", %{"poll-id" => poll_id, "choices" => choices}, socket) do
    poll_id = poll_id |> to_string() |> String.trim()

    with %User{} = user <- socket.assigns.current_user,
         true <- flake_id?(poll_id),
         %{type: "Question"} = question <- Objects.get(poll_id),
         choices <- parse_choices(choices),
         {:ok, _updated} <- Publish.vote_on_poll(user, question, choices) do
      {:noreply,
       socket
       |> put_flash(:info, "Vote submitted!")
       |> refresh_thread()}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to vote on polls.")}

      {:error, :already_voted} ->
        {:noreply, put_flash(socket, :error, "You have already voted on this poll.")}

      {:error, :poll_expired} ->
        {:noreply, put_flash(socket, :error, "This poll has ended.")}

      {:error, :own_poll} ->
        {:noreply, put_flash(socket, :error, "You cannot vote on your own poll.")}

      {:error, :multiple_choices_not_allowed} ->
        {:noreply, put_flash(socket, :error, "This poll only allows a single choice.")}

      {:error, :invalid_choice} ->
        {:noreply, put_flash(socket, :error, "Invalid poll option selected.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not submit vote.")}
    end
  end

  def handle_event("vote_on_poll", %{"poll-id" => _poll_id}, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, put_flash(socket, :error, "Register to vote on polls.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Please select at least one option.")}
    end
  end

  def handle_event("delete_post", %{"id" => id}, socket) do
    post_id = id |> to_string() |> String.trim()

    with %User{} = user <- socket.assigns.current_user,
         true <- flake_id?(post_id),
         {:ok, _delete} <- Interactions.delete_post(user, post_id) do
      socket =
        case socket.assigns.status do
          %{object: %{id: ^post_id}} ->
            socket
            |> put_flash(:info, "Post deleted.")
            |> push_navigate(to: timeline_href(user, socket.assigns.back_timeline))

          _ ->
            socket
            |> put_flash(:info, "Post deleted.")
            |> refresh_thread()
        end

      {:noreply, socket}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to delete posts.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not delete post.")}
    end
  end

  def handle_event("reply_change", %{"reply" => %{} = reply_params}, socket) do
    reply_params = Map.merge(default_reply_params(), reply_params)
    media_alt = Map.get(reply_params, "media_alt", %{})

    reply_options_open? = Param.truthy?(Map.get(reply_params, "ui_options_open"))

    reply_cw_open? =
      Param.truthy?(Map.get(reply_params, "ui_cw_open")) ||
        reply_params |> Map.get("spoiler_text", "") |> to_string() |> String.trim() != ""

    {:noreply,
     assign(socket,
       reply_form: Phoenix.Component.to_form(reply_params, as: :reply),
       reply_media_alt: media_alt,
       reply_options_open?: reply_options_open?,
       reply_cw_open?: reply_cw_open?
     )}
  end

  def handle_event("create_reply", %{"reply" => %{} = reply_params}, socket) do
    reply_params = Map.merge(default_reply_params(), reply_params)
    content = reply_params |> Map.get("content", "") |> to_string()
    media_alt = Map.get(reply_params, "media_alt", %{})
    visibility = Map.get(reply_params, "visibility", "public")
    spoiler_text = Map.get(reply_params, "spoiler_text")
    sensitive = Map.get(reply_params, "sensitive")
    language = Map.get(reply_params, "language")

    reply_options_open? = Param.truthy?(Map.get(reply_params, "ui_options_open"))

    reply_cw_open? =
      Param.truthy?(Map.get(reply_params, "ui_cw_open")) ||
        reply_params |> Map.get("spoiler_text", "") |> to_string() |> String.trim() != ""

    in_reply_to = reply_params |> Map.get("in_reply_to", "") |> to_string() |> String.trim()

    with %User{} = user <- socket.assigns.current_user,
         true <- in_reply_to != "" do
      upload = socket.assigns.uploads.reply_media

      cond do
        Enum.any?(upload.entries, &(!&1.done?)) ->
          {:noreply,
           socket
           |> put_flash(:error, "Wait for attachments to finish uploading.")
           |> assign(
             reply_form: Phoenix.Component.to_form(reply_params, as: :reply),
             reply_media_alt: media_alt,
             reply_options_open?: reply_options_open?,
             reply_cw_open?: reply_cw_open?
           )}

        upload_has_errors?(upload) ->
          {:noreply,
           socket
           |> put_flash(:error, "Remove invalid attachments before posting.")
           |> assign(
             reply_form: Phoenix.Component.to_form(reply_params, as: :reply),
             reply_media_alt: media_alt,
             reply_options_open?: reply_options_open?,
             reply_cw_open?: reply_cw_open?
           )}

        true ->
          attachments =
            consume_uploaded_entries(socket, :reply_media, fn %{path: path}, entry ->
              upload = %Plug.Upload{
                path: path,
                filename: entry.client_name,
                content_type: entry.client_type
              }

              description = media_alt |> Map.get(entry.ref, "") |> to_string() |> String.trim()

              with {:ok, url_path} <- MediaStorage.store_media(user, upload),
                   {:ok, object} <-
                     Media.create_media_object(user, upload, url_path, description: description) do
                {:ok, object.data}
              else
                {:error, reason} -> {:ok, {:error, reason}}
              end
            end)

          case Enum.find(attachments, &match?({:error, _}, &1)) do
            {:error, _reason} ->
              {:noreply,
               socket
               |> put_flash(:error, "Could not upload attachment.")
               |> assign(
                 reply_form: Phoenix.Component.to_form(reply_params, as: :reply),
                 reply_media_alt: media_alt,
                 reply_options_open?: reply_options_open?,
                 reply_cw_open?: reply_cw_open?
               )}

            nil ->
              case Publish.post_note(user, content,
                     in_reply_to: in_reply_to,
                     attachments: attachments,
                     visibility: visibility,
                     spoiler_text: spoiler_text,
                     sensitive: sensitive,
                     language: language
                   ) do
                {:ok, _create} ->
                  {:noreply,
                   socket
                   |> put_flash(:info, "Reply posted.")
                   |> refresh_thread()
                   |> assign(
                     reply_to_ap_id: nil,
                     reply_to_handle: nil,
                     reply_form: Phoenix.Component.to_form(default_reply_params(), as: :reply),
                     reply_media_alt: %{},
                     reply_options_open?: false,
                     reply_cw_open?: false
                   )
                   |> push_event("reply_modal_close", %{})}

                {:error, :too_long} ->
                  {:noreply,
                   socket
                   |> put_flash(:error, "Reply is too long.")
                   |> assign(
                     reply_form: Phoenix.Component.to_form(reply_params, as: :reply),
                     reply_media_alt: media_alt,
                     reply_options_open?: reply_options_open?,
                     reply_cw_open?: reply_cw_open?
                   )}

                {:error, :empty} ->
                  {:noreply,
                   socket
                   |> put_flash(:error, "Reply can't be empty.")
                   |> assign(
                     reply_form: Phoenix.Component.to_form(reply_params, as: :reply),
                     reply_media_alt: media_alt,
                     reply_options_open?: reply_options_open?,
                     reply_cw_open?: reply_cw_open?
                   )}

                _ ->
                  {:noreply,
                   socket
                   |> put_flash(:error, "Could not post reply.")
                   |> assign(
                     reply_form: Phoenix.Component.to_form(reply_params, as: :reply),
                     reply_media_alt: media_alt,
                     reply_options_open?: reply_options_open?,
                     reply_cw_open?: reply_cw_open?
                   )}
              end
          end
      end
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to reply.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not post reply.")}
    end
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
            <div class="flex flex-wrap items-center justify-between gap-3 border-2 border-[color:var(--border-default)] bg-[color:var(--bg-base)] px-4 py-3">
              <.link
                navigate={timeline_href(@current_user, @back_timeline)}
                class="inline-flex items-center gap-2 border-2 border-[color:var(--border-default)] bg-[color:var(--bg-base)] px-4 py-2 text-xs font-bold uppercase tracking-wide text-[color:var(--text-secondary)] transition hover:bg-[color:var(--text-primary)] hover:text-[color:var(--bg-base)] focus-visible:outline-none focus-brutal"
                aria-label="Back to timeline"
              >
                <.icon name="hero-arrow-left" class="size-4" /> Timeline
              </.link>

              <div class="text-right">
                <p class="text-lg font-bold text-[color:var(--text-primary)]">Post</p>
                <p class="mt-1 font-mono text-xs uppercase text-[color:var(--text-muted)]">
                  {if @status.object.local, do: "Local status", else: "Remote status"}
                </p>
              </div>
            </div>

            <div class="space-y-6" data-role="status-thread">
              <div :if={@ancestors != []} data-role="thread-ancestors" class="space-y-4">
                <div class="flex items-center justify-between gap-3 px-1">
                  <p class="text-xs font-bold uppercase tracking-wide text-[color:var(--text-muted)]">
                    Context
                  </p>
                  <span class="font-mono text-xs font-bold text-[color:var(--text-muted)]">
                    {length(@ancestors)}
                  </span>
                </div>

                <StatusCard.status_card
                  :for={entry <- @ancestors}
                  id={"post-#{entry.object.id}"}
                  entry={entry}
                  current_user={@current_user}
                  back_timeline={@back_timeline}
                  reply_mode={:modal}
                />
              </div>

              <% status_parent = reply_parent_info(@thread_index, @status.object) %>
              <div
                :if={@thread_missing_context?}
                data-role="thread-missing-context"
                class="flex items-start gap-3 border-2 border-[color:var(--border-default)] bg-[color:var(--bg-subtle)] px-4 py-4 text-sm text-[color:var(--text-secondary)]"
              >
                <span class="mt-0.5 inline-flex h-9 w-9 shrink-0 items-center justify-center border border-[color:var(--border-default)] bg-[color:var(--bg-base)] text-[color:var(--text-secondary)]">
                  <.icon name="hero-arrow-path" class="size-5" />
                </span>
                <div class="min-w-0">
                  <p class="font-bold text-[color:var(--text-primary)]">Fetching context…</p>
                  <p class="mt-1 leading-relaxed">
                    This post replies to something we haven't fetched yet. We'll try to pull in the missing
                    thread context in the background.
                  </p>

                  <div class="mt-5 space-y-4">
                    <.skeleton_status_card
                      :for={_ <- 1..2}
                      class="border-2 border-[color:var(--border-default)]"
                    />
                  </div>

                  <div :if={@thread_context_retry_visible?} class="mt-4">
                    <.button
                      type="button"
                      size="sm"
                      variant="secondary"
                      data-role="thread-fetch-context"
                      phx-click="fetch_thread_context"
                      phx-disable-with="Retrying…"
                    >
                      Retry
                    </.button>
                  </div>
                </div>
              </div>

              <div
                :if={is_map(status_parent)}
                data-role="thread-replying-to"
                data-parent-id={status_parent.dom_id}
                class="flex items-center gap-2 border border-[color:var(--border-muted)] bg-[color:var(--bg-subtle)] px-4 py-2 text-xs font-bold text-[color:var(--text-secondary)]"
              >
                <.icon name="hero-arrow-uturn-left" class="size-4" />
                <a
                  href={"##{status_parent.dom_id}"}
                  class="text-[color:var(--link)] underline underline-offset-2 transition hover:text-[color:var(--text-primary)]"
                >
                  Replying to {status_parent.handle}
                </a>
              </div>

              <div
                id="thread-focus"
                data-role="thread-focus"
                phx-hook="StatusAutoScroll"
                class="ring-2 ring-[color:var(--border-default)]"
              >
                <StatusCard.status_card
                  id={"post-#{@status.object.id}"}
                  entry={@status}
                  current_user={@current_user}
                  back_timeline={@back_timeline}
                  reply_mode={:modal}
                />
              </div>

              <div data-role="thread-replies" class="space-y-4">
                <div class="flex items-center justify-between gap-3 px-1">
                  <p class="text-xs font-bold uppercase tracking-wide text-[color:var(--text-muted)]">
                    Replies
                  </p>
                  <span class="font-mono text-xs font-bold text-[color:var(--text-muted)]">
                    {length(@descendants)}
                  </span>
                </div>

                <div
                  :if={@descendants == [] and @thread_fetching_replies?}
                  data-role="thread-replies-fetching"
                  class="border-2 border-[color:var(--border-default)] bg-[color:var(--bg-subtle)] p-6 text-sm text-[color:var(--text-secondary)]"
                >
                  <p class="font-bold text-[color:var(--text-primary)]">Fetching replies…</p>

                  <div class="mt-5 space-y-4">
                    <.skeleton_status_card
                      :for={_ <- 1..3}
                      class="border-2 border-[color:var(--border-default)]"
                    />
                  </div>

                  <div :if={@thread_replies_retry_visible?} class="mt-5">
                    <.button
                      type="button"
                      size="sm"
                      variant="secondary"
                      data-role="thread-fetch-replies"
                      phx-click="fetch_thread_replies"
                      phx-disable-with="Retrying…"
                    >
                      Retry
                    </.button>
                  </div>
                </div>

                <div
                  :if={@descendants == [] and not @thread_fetching_replies?}
                  data-role="thread-replies-empty"
                  class="border-2 border-[color:var(--border-default)] bg-[color:var(--bg-subtle)] p-6 text-sm text-[color:var(--text-secondary)]"
                >
                  No replies yet.
                </div>

                <div
                  :for={%{entry: entry, depth: depth} <- @descendants}
                  data-role="thread-descendant"
                  data-depth={depth}
                  style={"--thread-indent: #{thread_indent(depth)}px"}
                  class="relative pl-[calc(var(--thread-indent)+2.5rem)]"
                >
                  <span
                    data-role="thread-rail"
                    class="absolute bottom-0 left-[var(--thread-indent)] top-0 w-px bg-[color:var(--border-muted)]"
                    aria-hidden="true"
                  >
                  </span>

                  <span
                    data-role="thread-node"
                    class="absolute left-[calc(var(--thread-indent)-0.375rem)] top-10 h-3 w-3 border border-[color:var(--border-default)] bg-[color:var(--bg-base)]"
                    aria-hidden="true"
                  >
                  </span>

                  <span
                    data-role="thread-connector"
                    class="absolute left-[var(--thread-indent)] top-11 h-px w-6 bg-[color:var(--border-muted)]"
                    aria-hidden="true"
                  >
                  </span>

                  <% parent_info = reply_parent_info(@thread_index, entry.object) %>

                  <div
                    :if={is_map(parent_info)}
                    data-role="thread-replying-to"
                    data-parent-id={parent_info.dom_id}
                    class="mb-2 flex items-center gap-2 text-xs font-bold text-[color:var(--text-muted)]"
                  >
                    <.icon name="hero-arrow-uturn-left" class="size-4" />
                    <a
                      href={"##{parent_info.dom_id}"}
                      class="text-[color:var(--link)] underline underline-offset-2 transition hover:text-[color:var(--text-primary)]"
                    >
                      Replying to {parent_info.handle}
                    </a>
                  </div>

                  <StatusCard.status_card
                    id={"post-#{entry.object.id}"}
                    entry={entry}
                    current_user={@current_user}
                    back_timeline={@back_timeline}
                    reply_mode={:modal}
                  />
                </div>
              </div>
            </div>
          </section>
        <% else %>
          <section class="border-2 border-[color:var(--border-default)] bg-[color:var(--bg-base)] p-8 text-center">
            <p class="text-xl font-bold text-[color:var(--text-primary)]">Post not found</p>
            <p class="mt-3 text-sm text-[color:var(--text-secondary)]">
              This status may have been deleted or was never fetched by this instance.
            </p>
            <div class="mt-6 flex justify-center">
              <.link
                navigate={timeline_href(@current_user, @back_timeline)}
                class="inline-flex items-center gap-2 border-2 border-[color:var(--border-default)] bg-[color:var(--text-primary)] px-6 py-3 text-sm font-bold text-[color:var(--bg-base)] transition hover:bg-[color:var(--accent-primary-hover)] focus-visible:outline-none focus-brutal"
              >
                <.icon name="hero-home" class="size-5" /> Go to timeline
              </.link>
            </div>
          </section>
        <% end %>
      </AppShell.app_shell>

      <ReplyModal.reply_modal
        :if={@current_user}
        form={@reply_form}
        upload={@uploads.reply_media}
        media_alt={@reply_media_alt}
        reply_to_handle={@reply_to_handle}
        current_user_handle={@current_user_handle}
        prefill_mention_handles={@reply_prefill_mention_handles}
        prefill_in_reply_to={@reply_to_ap_id}
        mention_suggestions={@mention_suggestions}
        max_chars={reply_max_chars()}
        options_open?={@reply_options_open?}
        cw_open?={@reply_cw_open?}
      />

      <MediaViewer.media_viewer
        viewer={%{items: [], index: 0}}
        open={false}
      />
    </Layouts.app>
    """
  end

  defp object_for_uuid_param(uuid) when is_binary(uuid) do
    uuid = String.trim(uuid)

    if uuid == "" do
      nil
    else
      ap_id = Endpoint.url() <> "/objects/" <> uuid
      Objects.get_by_ap_id(ap_id) || Objects.get(uuid)
    end
  end

  defp object_for_uuid_param(_uuid), do: nil

  defp maybe_redirect_to_canonical_permalink(
         socket,
         %{"nickname" => nickname, "uuid" => uuid} = params
       )
       when is_binary(nickname) and is_binary(uuid) do
    with %{actor: actor} <- socket.assigns.status,
         {canonical, profile_path} when is_binary(canonical) and is_binary(profile_path) <-
           canonical_profile_path(actor),
         true <- canonical != "" and canonical != nickname,
         to when is_binary(to) <- canonical_permalink_path(profile_path, uuid, params) do
      if connected?(socket) do
        push_navigate(socket, to: to)
      else
        redirect(socket, to: to)
      end
    else
      _ -> socket
    end
  end

  defp maybe_redirect_to_canonical_permalink(socket, _params), do: socket

  defp canonical_profile_path(%{handle: handle, ap_id: ap_id}) do
    canonical_profile_path(handle, ap_id)
  end

  defp canonical_profile_path(%{handle: handle}) do
    canonical_profile_path(handle, nil)
  end

  defp canonical_profile_path(handle, ap_id) when is_binary(handle) do
    handle = String.trim(handle)

    case ProfilePaths.profile_path(handle) do
      "/@" <> rest = profile_path ->
        {URI.decode(rest), profile_path}

      _ ->
        canonical_profile_path_from_ap_id(ap_id)
    end
  end

  defp canonical_profile_path(_handle, ap_id) do
    canonical_profile_path_from_ap_id(ap_id)
  end

  defp canonical_profile_path_from_ap_id(ap_id) when is_binary(ap_id) do
    with %URI{} = uri <- URI.parse(ap_id),
         domain when is_binary(domain) and domain != "" <- Domain.from_uri(uri),
         path when is_binary(path) and path != "" <- uri.path,
         nickname when is_binary(nickname) <-
           path |> String.trim("/") |> path_basename(),
         true <- nickname != "",
         canonical <- nickname <> "@" <> domain,
         profile_path when is_binary(profile_path) <- ProfilePaths.profile_path(canonical) do
      {canonical, profile_path}
    else
      _ -> nil
    end
  end

  defp canonical_profile_path_from_ap_id(_ap_id), do: nil

  defp path_basename(path) when is_binary(path) do
    case String.split(path, "/", trim: true) do
      [] -> ""
      segments -> List.last(segments)
    end
  end

  defp canonical_permalink_path(profile_path, uuid, params)
       when is_binary(profile_path) and is_binary(uuid) do
    if uuid == "" do
      nil
    else
      query_params = Map.drop(params, ["nickname", "uuid"])
      query = URI.encode_query(query_params)

      if query == "" do
        profile_path <> "/" <> uuid
      else
        profile_path <> "/" <> uuid <> "?" <> query
      end
    end
  end

  defp notifications_count(nil), do: 0

  defp notifications_count(%User{} = user) do
    user
    |> Notifications.list_for_user(limit: 20, include_offers?: true)
    |> length()
  end

  defp upload_has_errors?(%{errors: errors, entries: entries} = upload)
       when is_list(errors) and is_list(entries) do
    upload.errors != [] or
      Enum.any?(entries, fn entry ->
        not entry.valid? or upload_errors(upload, entry) != []
      end)
  end

  defp upload_has_errors?(_upload), do: false

  defp refresh_thread(socket) do
    current_user = socket.assigns.current_user

    case socket.assigns.status do
      %{object: %{type: "Note"} = note} ->
        note =
          case note.ap_id do
            ap_id when is_binary(ap_id) and ap_id != "" ->
              case Objects.get_by_ap_id(ap_id) do
                %Egregoros.Object{} = latest -> latest
                _ -> note
              end

            _ ->
              note
          end

        status_entry = StatusVM.decorate(note, current_user)

        raw_ancestors = Objects.thread_ancestors(note)

        ancestor_entries =
          raw_ancestors
          |> Enum.filter(&Objects.visible_to?(&1, current_user))
          |> StatusVM.decorate_many(current_user)

        descendant_entries = decorate_descendants(note, current_user)
        thread_index = build_thread_index(status_entry, ancestor_entries, descendant_entries)

        fetching_replies? =
          note.local == false and note |> replies_url() |> normalize_binary() != "" and
            descendant_entries == [] and is_nil(note.thread_replies_checked_at)

        parent_ap_id =
          note.data
          |> Map.get("inReplyTo")
          |> in_reply_to_ap_id()
          |> normalize_binary()

        missing_parent? = parent_ap_id != "" and raw_ancestors == []

        socket
        |> assign(
          status: status_entry,
          ancestors: ancestor_entries,
          descendants: descendant_entries,
          thread_index: thread_index,
          thread_missing_context?: missing_parent?,
          thread_fetching_replies?: fetching_replies?
        )

      %{object: %{type: "Question"} = question} ->
        question =
          case question.ap_id do
            ap_id when is_binary(ap_id) and ap_id != "" ->
              case Objects.get_by_ap_id(ap_id) do
                %Egregoros.Object{} = latest -> latest
                _ -> question
              end

            _ ->
              question
          end

        status_entry = StatusVM.decorate(question, current_user)
        thread_index = build_thread_index(status_entry, [], [])

        socket
        |> assign(
          status: status_entry,
          ancestors: [],
          descendants: [],
          thread_index: thread_index,
          thread_missing_context?: false,
          thread_fetching_replies?: false
        )

      _ ->
        socket
    end
  end

  defp thread_relevant?(socket, %Egregoros.Object{} = object) do
    thread_ap_ids = thread_object_ap_ids(socket.assigns)

    object_ap_id =
      object
      |> Map.get(:ap_id)
      |> to_string()
      |> String.trim()

    in_reply_to =
      object
      |> Map.get(:data, %{})
      |> Map.get("inReplyTo")
      |> in_reply_to_ap_id()

    cond do
      object_ap_id != "" and object_ap_id in thread_ap_ids ->
        true

      is_binary(in_reply_to) and in_reply_to in thread_ap_ids ->
        true

      object_ap_id != "" and object_ap_id in thread_parent_ap_ids(socket.assigns) ->
        true

      true ->
        false
    end
  end

  defp thread_relevant?(_socket, _object), do: false

  defp schedule_thread_retry(kind) when kind in [:context, :replies] do
    _ = Process.send_after(self(), {:thread_retry_available, kind}, @thread_retry_delay_ms)
    :ok
  end

  defp schedule_thread_retry(_kind), do: :ok

  defp thread_object_ap_ids(%{status: %{object: %{ap_id: ap_id}}} = assigns) do
    ap_id = ap_id |> to_string() |> String.trim()

    ancestors =
      assigns
      |> Map.get(:ancestors, [])
      |> Enum.map(fn
        %{object: %{ap_id: ap_id}} -> ap_id |> to_string() |> String.trim()
        _ -> ""
      end)

    descendants =
      assigns
      |> Map.get(:descendants, [])
      |> Enum.map(fn
        %{entry: %{object: %{ap_id: ap_id}}} -> ap_id |> to_string() |> String.trim()
        _ -> ""
      end)

    [ap_id | ancestors ++ descendants]
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp thread_object_ap_ids(_assigns), do: []

  defp thread_parent_ap_ids(%{} = assigns) do
    assigns
    |> thread_objects()
    |> Enum.map(fn %{data: data} -> data |> Map.get("inReplyTo") |> in_reply_to_ap_id() end)
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp thread_parent_ap_ids(_assigns), do: []

  defp thread_objects(%{} = assigns) do
    status_object =
      case Map.get(assigns, :status) do
        %{object: %{} = object} -> object
        _ -> nil
      end

    ancestor_objects =
      assigns
      |> Map.get(:ancestors, [])
      |> Enum.map(fn
        %{object: %{} = object} -> object
        _ -> nil
      end)

    descendant_objects =
      assigns
      |> Map.get(:descendants, [])
      |> Enum.map(fn
        %{entry: %{object: %{} = object}} -> object
        _ -> nil
      end)

    [status_object | ancestor_objects ++ descendant_objects]
    |> Enum.reject(&is_nil/1)
  end

  defp decorate_descendants(%{} = note, current_user) do
    descendants =
      note
      |> Objects.thread_descendants()
      |> Enum.filter(&Objects.visible_to?(&1, current_user))

    depths = descendant_depths(note.ap_id, descendants)

    descendants
    |> StatusVM.decorate_many(current_user)
    |> Enum.zip(depths)
    |> Enum.map(fn {entry, depth} -> %{entry: entry, depth: depth} end)
  end

  defp decorate_descendants(_note, _current_user), do: []

  defp descendant_depths(root_ap_id, descendants)
       when is_binary(root_ap_id) and is_list(descendants) do
    {depths, _depth_map} =
      Enum.map_reduce(descendants, %{root_ap_id => 0}, fn descendant, depth_map ->
        parent_ap_id =
          descendant
          |> Map.get(:data, %{})
          |> Map.get("inReplyTo")
          |> in_reply_to_ap_id()

        depth = Map.get(depth_map, parent_ap_id, 0) + 1
        {depth, Map.put(depth_map, Map.get(descendant, :ap_id), depth)}
      end)

    depths
  end

  defp descendant_depths(_root_ap_id, _descendants), do: []

  defp build_thread_index(status_entry, ancestor_entries, descendant_entries)
       when is_list(ancestor_entries) and is_list(descendant_entries) do
    entries =
      [status_entry | ancestor_entries ++ Enum.map(descendant_entries, &Map.get(&1, :entry))]
      |> Enum.filter(&is_map/1)

    Enum.reduce(entries, %{dom_id_by_ap_id: %{}, handle_by_ap_id: %{}}, fn entry, acc ->
      object = Map.get(entry, :object) || %{}
      actor = Map.get(entry, :actor) || %{}

      ap_id =
        case Map.get(object, :ap_id) do
          value when is_binary(value) -> String.trim(value)
          _ -> ""
        end

      object_id = Map.get(object, :id)

      handle =
        case Map.get(actor, :handle) do
          value when is_binary(value) -> String.trim(value)
          _ -> ""
        end

      if ap_id != "" and is_binary(object_id) and object_id != "" do
        acc
        |> put_in([:dom_id_by_ap_id, ap_id], "post-#{object_id}")
        |> put_in([:handle_by_ap_id, ap_id], handle)
      else
        acc
      end
    end)
  end

  defp build_thread_index(_status_entry, _ancestor_entries, _descendant_entries) do
    %{dom_id_by_ap_id: %{}, handle_by_ap_id: %{}}
  end

  defp reply_parent_info(
         %{dom_id_by_ap_id: dom_id_by_ap_id, handle_by_ap_id: handle_by_ap_id},
         object
       )
       when is_map(dom_id_by_ap_id) and is_map(handle_by_ap_id) and is_map(object) do
    parent_ap_id =
      object
      |> Map.get(:data, %{})
      |> Map.get("inReplyTo")
      |> in_reply_to_ap_id()

    parent_ap_id =
      case parent_ap_id do
        ap_id when is_binary(ap_id) -> String.trim(ap_id)
        _ -> nil
      end

    dom_id = if is_binary(parent_ap_id), do: Map.get(dom_id_by_ap_id, parent_ap_id), else: nil
    handle = if is_binary(parent_ap_id), do: Map.get(handle_by_ap_id, parent_ap_id), else: nil

    if is_binary(dom_id) and dom_id != "" and is_binary(handle) and handle != "" do
      %{dom_id: dom_id, handle: handle}
    else
      nil
    end
  end

  defp reply_parent_info(_thread_index, _object), do: nil

  defp in_reply_to_ap_id(value) when is_binary(value), do: value
  defp in_reply_to_ap_id(%{"id" => id}) when is_binary(id), do: id
  defp in_reply_to_ap_id(_), do: nil

  defp replies_url(%{data: %{} = data}) do
    data
    |> Map.get("replies")
    |> extract_link()
  end

  defp replies_url(_object), do: nil

  defp extract_link(value) when is_binary(value), do: value
  defp extract_link(%{"id" => id}) when is_binary(id), do: id
  defp extract_link(%{id: id}) when is_binary(id), do: id
  defp extract_link(_value), do: nil

  defp normalize_binary(value) when is_binary(value), do: String.trim(value)
  defp normalize_binary(_value), do: ""

  defp thread_indent(depth) when is_integer(depth) do
    depth = depth |> max(1) |> min(5)
    depth * 24
  end

  defp thread_indent(_depth), do: 0

  defp reply_max_chars, do: @reply_max_chars

  defp default_reply_params do
    %{
      "content" => "",
      "spoiler_text" => "",
      "visibility" => "public",
      "sensitive" => "false",
      "language" => "",
      "ui_cw_open" => "false",
      "ui_options_open" => "false",
      "media_alt" => %{}
    }
  end

  defp mention_handle_names(%{data: %{} = data}) do
    local_domains = local_domains()

    data
    |> Map.get("tag", [])
    |> List.wrap()
    |> Enum.flat_map(&mention_handle_from_tag(&1, local_domains))
    |> Enum.uniq()
  end

  defp mention_handle_names(_object), do: []

  defp mention_handle_from_tag(tag, local_domains) when is_list(local_domains) do
    {name, href} =
      case tag do
        %{"type" => "Mention"} = tag ->
          {Map.get(tag, "name") || Map.get(tag, :name),
           Map.get(tag, "href") || Map.get(tag, :href) || Map.get(tag, "id") || Map.get(tag, :id)}

        %{type: "Mention"} = tag ->
          {Map.get(tag, :name) || Map.get(tag, "name"),
           Map.get(tag, :href) || Map.get(tag, "href") || Map.get(tag, :id) || Map.get(tag, "id")}

        _ ->
          {nil, nil}
      end

    with handle when is_binary(handle) <- handle_for_prefill(name, href, local_domains) do
      [handle]
    else
      _ -> []
    end
  end

  defp mention_handle_from_tag(_tag, _local_domains), do: []

  defp handle_for_prefill(name, href, local_domains)
       when is_binary(name) and is_list(local_domains) do
    name = name |> String.trim() |> String.trim_leading("@")

    case Mentions.parse(name) do
      {:ok, nickname, host} ->
        host = host || mention_host_from_href(href)

        cond do
          is_binary(host) and host != "" and host not in local_domains -> "@#{nickname}@#{host}"
          true -> "@#{nickname}"
        end

      :error ->
        nil
    end
  end

  defp handle_for_prefill(_name, _href, _local_domains), do: nil

  defp mention_host_from_href(href) when is_binary(href) do
    href = String.trim(href)

    if href == "" do
      nil
    else
      href |> URI.parse() |> Domain.from_uri()
    end
  end

  defp mention_host_from_href(_href), do: nil

  defp local_domains do
    case URI.parse(Endpoint.url()) do
      %URI{} = uri -> Domain.aliases_from_uri(uri)
      _ -> []
    end
  end

  defp back_timeline_from_params(params, current_user) when is_map(params) do
    timeline =
      (Map.get(params, "back_timeline") || "")
      |> to_string()
      |> String.trim()
      |> String.downcase()

    case timeline do
      "public" -> :public
      "home" -> :home
      _ -> if match?(%User{}, current_user), do: :home, else: :public
    end
  end

  defp back_timeline_from_params(_params, current_user) do
    if match?(%User{}, current_user), do: :home, else: :public
  end

  defp timeline_href(%{id: _}, :public), do: ~p"/?timeline=public" <> "&restore_scroll=1"
  defp timeline_href(%{id: _}, _timeline), do: ~p"/?timeline=home" <> "&restore_scroll=1"
  defp timeline_href(_user, _timeline), do: ~p"/?timeline=public" <> "&restore_scroll=1"

  defp parse_choices(choices) when is_list(choices) do
    choices
    |> Enum.map(fn
      choice when is_integer(choice) ->
        choice

      choice when is_binary(choice) ->
        case Integer.parse(choice) do
          {int, ""} -> int
          _ -> nil
        end

      _ ->
        nil
    end)
    |> Enum.filter(&is_integer/1)
  end

  defp parse_choices(choice) when is_binary(choice) do
    case Integer.parse(choice) do
      {int, ""} -> [int]
      _ -> []
    end
  end

  defp parse_choices(_choices), do: []

  defp flake_id?(id) when is_binary(id) do
    id = String.trim(id)
    byte_size(id) == 18 and FlakeId.flake_id?(id)
  end

  defp flake_id?(_id), do: false
end
