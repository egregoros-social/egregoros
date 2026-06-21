defmodule EgregorosWeb.SearchLive do
  use EgregorosWeb, :live_view

  alias Egregoros.Federation
  alias Egregoros.Badges
  alias Egregoros.Interactions
  alias Egregoros.Media
  alias Egregoros.MediaStorage
  alias Egregoros.Notifications
  alias Egregoros.Objects
  alias Egregoros.Publish
  alias Egregoros.Relationships
  alias Egregoros.User
  alias Egregoros.Users
  alias EgregorosWeb.MentionAutocomplete
  alias EgregorosWeb.Param
  alias EgregorosWeb.ProfilePaths
  alias EgregorosWeb.URL
  alias EgregorosWeb.ViewModels.Actor, as: ActorVM
  alias EgregorosWeb.ViewModels.Status, as: StatusVM

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
        notifications_count: notifications_count(current_user),
        followed_tags: followed_tags(current_user, 12),
        mention_suggestions: %{},
        remote_follow_queued?: false,
        reply_form: Phoenix.Component.to_form(default_reply_params(), as: :reply),
        reply_media_alt: %{},
        reply_options_open?: false,
        reply_cw_open?: false
      )
      |> apply_params(params)
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

  def handle_event("follow_remote", _params, socket) do
    with %User{} = user <- socket.assigns.current_user,
         handle when is_binary(handle) and handle != "" <- socket.assigns.remote_handle,
         {:ok, result} <- Federation.follow_remote_async(user, handle) do
      {socket, queued?} =
        case result do
          %User{} = remote_user ->
            handle = ActorVM.handle(remote_user, remote_user.ap_id)
            {put_flash(socket, :info, "Sent a follow request to #{handle}."), false}

          :queued ->
            {put_flash(socket, :info, "Queued follow request for @#{handle}."), true}
        end

      {:noreply,
       socket
       |> apply_params(%{"q" => socket.assigns.query})
       |> assign(remote_follow_queued?: queued?)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Login to follow remote accounts.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not follow remote account.")}
    end
  end

  def handle_event("copied_link", _params, socket) do
    {:noreply, put_flash(socket, :info, "Copied link to clipboard.")}
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

  def handle_event("cancel_reply_media", %{"ref" => ref}, socket) do
    {:noreply,
     socket
     |> cancel_upload(:reply_media, ref)
     |> assign(:reply_media_alt, Map.delete(socket.assigns.reply_media_alt, ref))}
  end

  def handle_event("create_reply", %{"reply" => %{} = reply_params}, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, put_flash(socket, :error, "Register to reply.")}

      user ->
        in_reply_to = reply_params |> Map.get("in_reply_to", "") |> to_string() |> String.trim()

        if in_reply_to != "" do
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

            upload.errors != [] or Enum.any?(upload.entries, &(!&1.valid?)) ->
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

                  description =
                    media_alt |> Map.get(entry.ref, "") |> to_string() |> String.trim()

                  with {:ok, url_path} <- MediaStorage.store_media(user, upload),
                       {:ok, object} <-
                         Media.create_media_object(user, upload, url_path,
                           description: description
                         ) do
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
                    {:ok, _reply} ->
                      {:noreply,
                       socket
                       |> put_flash(:info, "Reply posted.")
                       |> assign(
                         reply_form:
                           Phoenix.Component.to_form(default_reply_params(), as: :reply),
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
          {:noreply, put_flash(socket, :error, "Select a post to reply to.")}
        end
    end
  end

  def handle_event("toggle_like", %{"id" => id}, socket) do
    post_id = id |> to_string() |> String.trim()

    with %User{} = user <- socket.assigns.current_user,
         true <- flake_id?(post_id) do
      _ = Interactions.toggle_like(user, post_id)
      {:noreply, refresh_post(socket, post_id)}
    else
      _ -> {:noreply, socket}
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

      {:noreply, refresh_post(socket, post_id)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle_reaction", %{"id" => id, "emoji" => emoji}, socket) do
    post_id = id |> to_string() |> String.trim()

    with %User{} = user <- socket.assigns.current_user,
         true <- flake_id?(post_id),
         emoji when is_binary(emoji) <- to_string(emoji) do
      _ = Interactions.toggle_reaction(user, post_id, emoji)
      {:noreply, refresh_post(socket, post_id)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle_bookmark", %{"id" => id}, socket) do
    post_id = id |> to_string() |> String.trim()

    with %User{} = user <- socket.assigns.current_user,
         true <- flake_id?(post_id) do
      _ = Interactions.toggle_bookmark(user, post_id)
      {:noreply, refresh_post(socket, post_id)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delete_post", %{"id" => id}, socket) do
    post_id = id |> to_string() |> String.trim()

    with %User{} = user <- socket.assigns.current_user,
         true <- flake_id?(post_id),
         {:ok, _delete} <- Interactions.delete_post(user, post_id) do
      {:noreply,
       socket
       |> assign(
         post_results: Enum.reject(socket.assigns.post_results, &(&1.object.id == post_id))
       )
       |> put_flash(:info, "Deleted post.")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not delete post.")}
    end
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
                <p class="text-xs font-bold uppercase tracking-wide text-[color:var(--text-muted)]">
                  Search
                </p>
                <h2 class="mt-2 text-2xl font-bold text-[color:var(--text-primary)]">
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

          <section
            :if={@query == "" and @current_user != nil and @followed_tags != []}
            data-role="search-followed-tags"
            class="space-y-3"
          >
            <.card class="p-6">
              <p class="text-xs font-bold uppercase tracking-wide text-[color:var(--text-muted)]">
                Your tags
              </p>
              <h3 class="mt-2 text-xl font-bold text-[color:var(--text-primary)]">
                Followed hashtags
              </h3>
            </.card>

            <.card class="p-5">
              <div class="flex flex-wrap gap-2">
                <.link
                  :for={tag <- @followed_tags}
                  navigate={~p"/tags/#{tag}"}
                  data-role="search-followed-tag"
                  class="inline-flex items-center gap-2 border border-[color:var(--border-default)] bg-[color:var(--bg-subtle)] px-3 py-2 text-sm font-semibold text-[color:var(--text-primary)] transition hover:bg-[color:var(--bg-base)]"
                >
                  <.icon name="hero-hashtag" class="size-4 text-[color:var(--text-muted)]" />
                  <span>#{tag}</span>
                </.link>
              </div>
            </.card>
          </section>

          <div data-role="search-results" class="space-y-3">
            <.card
              :if={@remote_handle != nil and @current_user == nil}
              data_role="remote-follow"
              class="p-6"
            >
              <p class="text-sm font-bold text-[color:var(--text-primary)]">
                Follow a remote account
              </p>
              <p class="mt-2 text-sm text-[color:var(--text-secondary)]">
                Login to follow <span class="font-bold">{@remote_handle}</span>.
              </p>
              <div class="mt-4 flex flex-wrap items-center gap-2">
                <.button navigate={~p"/login"} size="sm">Login</.button>
                <.button navigate={~p"/register"} variant="secondary" size="sm">Register</.button>
              </div>
            </.card>

            <.card
              :if={@remote_handle != nil and @current_user != nil and @remote_follow_queued?}
              data_role="remote-follow"
              class="p-6"
            >
              <p class="text-sm font-bold text-[color:var(--text-primary)]">
                Remote follow queued
              </p>
              <p class="mt-2 text-sm text-[color:var(--text-secondary)]">
                Fetching <span class="font-bold">@{@remote_handle}</span>
                and sending your follow request.
              </p>
            </.card>

            <.card
              :if={
                @remote_handle != nil and @current_user != nil and !@remote_following? and
                  !@remote_follow_queued?
              }
              data_role="remote-follow"
              class="p-6"
            >
              <p class="text-sm font-bold text-[color:var(--text-primary)]">
                Follow a remote account
              </p>
              <p class="mt-2 text-sm text-[color:var(--text-secondary)]">
                Follow <span class="font-bold">{@remote_handle}</span> via ActivityPub.
              </p>
              <div class="mt-4">
                <.button
                  type="button"
                  data-role="remote-follow-button"
                  phx-click="follow_remote"
                  phx-disable-with="Following..."
                  size="sm"
                >
                  Follow
                </.button>
              </div>
            </.card>

            <.card
              :if={@remote_handle != nil and @current_user != nil and @remote_following?}
              data_role="remote-follow"
              class="p-6"
            >
              <p class="text-sm font-bold text-[color:var(--text-primary)]">
                Remote follow
              </p>
              <p class="mt-2 text-sm text-[color:var(--text-secondary)]">
                You are following <span class="font-bold">{@remote_handle}</span>.
              </p>
            </.card>

            <.card :if={@query != "" and @results == []} class="p-6">
              <p class="text-sm text-[color:var(--text-secondary)]">
                No matching accounts found.
              </p>
            </.card>

            <.card :if={@query == ""} class="p-6">
              <p class="text-sm text-[color:var(--text-secondary)]">
                Type a query to search for accounts and posts.
              </p>
            </.card>

            <.card :for={user <- @results} class="p-5">
              <.link
                navigate={ProfilePaths.profile_path(user)}
                class="flex items-center gap-4 focus-visible:outline-none focus-brutal"
              >
                <.avatar
                  name={user.name || user.nickname || user.ap_id}
                  src={URL.absolute(user.avatar_url, user.ap_id)}
                  size="lg"
                />

                <div class="min-w-0 flex-1">
                  <p class="truncate text-sm font-bold text-[color:var(--text-primary)]">
                    {user.name || user.nickname || user.ap_id}
                  </p>
                  <p
                    data-role="search-result-handle"
                    class="truncate font-mono text-xs text-[color:var(--text-muted)]"
                  >
                    {ActorVM.handle(user, user.ap_id)}
                  </p>
                </div>
              </.link>
            </.card>
          </div>

          <section
            :if={@tag_query != nil}
            data-role="search-tag-results"
            class="space-y-3"
          >
            <.card class="p-6">
              <p class="text-xs font-bold uppercase tracking-wide text-[color:var(--text-muted)]">
                Hashtags
              </p>
              <h3 class="mt-2 text-xl font-bold text-[color:var(--text-primary)]">
                Matching tags
              </h3>
            </.card>

            <.card class="p-5">
              <.link
                navigate={~p"/tags/#{@tag_query}"}
                data-role="search-tag-link"
                class="group flex items-center gap-4 focus-visible:outline-none focus-brutal"
              >
                <span class="inline-flex h-11 w-11 items-center justify-center border border-[color:var(--border-default)] bg-[color:var(--bg-subtle)] text-[color:var(--text-secondary)]">
                  <.icon name="hero-hashtag" class="size-5" />
                </span>

                <div class="min-w-0 flex-1">
                  <p class="truncate text-sm font-bold text-[color:var(--text-primary)]">
                    #{@tag_query}
                  </p>
                  <p class="mt-1 text-xs text-[color:var(--text-muted)]">
                    View tag timeline
                  </p>
                </div>

                <.icon
                  name="hero-chevron-right"
                  class="size-5 text-[color:var(--text-muted)] transition group-hover:translate-x-0.5"
                />
              </.link>
            </.card>
          </section>

          <section
            :if={@query != ""}
            data-role="search-post-results"
            class="space-y-3"
          >
            <.card class="p-6">
              <p class="text-xs font-bold uppercase tracking-wide text-[color:var(--text-muted)]">
                Posts
              </p>
              <h3 class="mt-2 text-xl font-bold text-[color:var(--text-primary)]">
                Matching notes
              </h3>
            </.card>

            <.card :if={@post_results == []} class="p-6">
              <p class="text-sm text-[color:var(--text-secondary)]">
                No matching posts found.
              </p>
            </.card>

            <StatusCard.status_card
              :for={entry <- @post_results}
              id={post_dom_id(entry)}
              entry={entry}
              current_user={@current_user}
              reply_mode={if @current_user, do: :modal, else: :navigate}
            />
          </section>
        </section>
      </AppShell.app_shell>

      <ReplyModal.reply_modal
        :if={@current_user}
        form={@reply_form}
        upload={@uploads.reply_media}
        media_alt={@reply_media_alt}
        current_user_handle={ActorVM.handle(@current_user, @current_user.ap_id)}
        mention_suggestions={@mention_suggestions}
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

  defp apply_params(socket, %{} = params) do
    q = params |> Map.get("q", "") |> to_string() |> String.trim()

    {search_query, remote_handle} = parse_query(q)

    tag_query =
      case q do
        "#" <> rest ->
          tag = rest |> String.trim()
          if valid_hashtag?(tag), do: tag, else: nil

        _ ->
          tag = q |> String.trim()

          if tag != "" and
               remote_handle == nil and
               !String.contains?(tag, " ") and
               !String.starts_with?(tag, "@") and
               valid_hashtag?(tag) and
               Objects.list_notes_by_hashtag(tag, limit: 1) != [] do
            tag
          else
            nil
          end
      end

    results =
      if search_query == "" do
        []
      else
        Users.search(search_query, limit: @page_size, current_user: socket.assigns.current_user)
      end

    post_results =
      if q == "" do
        []
      else
        q
        |> Objects.search_notes(limit: @page_size)
        |> StatusVM.decorate_many(socket.assigns[:current_user])
      end

    remote_following? =
      with %User{} = user <- socket.assigns[:current_user],
           handle when is_binary(handle) <- remote_handle,
           %User{} = target <- Users.get_by_handle(handle),
           %{} <- Relationships.get_by_type_actor_object("Follow", user.ap_id, target.ap_id) do
        true
      else
        _ -> false
      end

    assign(socket,
      query: q,
      tag_query: tag_query,
      remote_handle: remote_handle,
      remote_following?: remote_following?,
      remote_follow_queued?: false,
      post_results: post_results,
      results: results,
      search_form: Phoenix.Component.to_form(%{"q" => q}, as: :search)
    )
  end

  defp post_dom_id(%{object: %{id: id}}) when is_binary(id), do: "search-post-#{id}"
  defp post_dom_id(_post), do: Ecto.UUID.generate()

  defp refresh_post(socket, post_id) when is_binary(post_id) do
    current_user = socket.assigns.current_user

    case Objects.get(post_id) do
      %{type: type} = object when type in ["Note", "Question", "VerifiableCredential"] ->
        if Objects.visible_to?(object, current_user) do
          entry = StatusVM.decorate(object, current_user)

          assign(socket,
            post_results:
              Enum.map(socket.assigns.post_results, fn current ->
                if current.object.id == post_id, do: entry, else: current
              end)
          )
        else
          assign(socket,
            post_results:
              Enum.reject(socket.assigns.post_results, fn current ->
                current.object.id == post_id
              end)
          )
        end

      _ ->
        socket
    end
  end

  defp flake_id?(id) when is_binary(id) do
    id = String.trim(id)
    byte_size(id) == 18 and FlakeId.flake_id?(id)
  end

  defp flake_id?(_id), do: false

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

  defp valid_hashtag?(tag) when is_binary(tag) do
    Regex.match?(~r/^[\p{L}\p{N}_][\p{L}\p{N}_-]{0,63}$/u, tag)
  end

  defp valid_hashtag?(_tag), do: false

  defp normalize_hashtag(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.trim_leading("#")
    |> String.downcase()
  end

  defp normalize_hashtag(_name), do: ""

  defp followed_tags(%User{ap_id: actor_ap_id}, limit)
       when is_binary(actor_ap_id) and actor_ap_id != "" and is_integer(limit) do
    Relationships.list_by_type_actor("FollowTag", actor_ap_id, limit: limit)
    |> Enum.map(&normalize_hashtag(&1.object))
    |> Enum.uniq()
    |> Enum.filter(&valid_hashtag?/1)
    |> Enum.take(limit)
  end

  defp followed_tags(_user, _limit), do: []

  defp parse_query(query) when is_binary(query) do
    query = String.trim(query)
    trimmed = String.trim_leading(query, "@")

    case String.split(trimmed, "@", parts: 2) do
      [nickname, domain] when nickname != "" and domain != "" ->
        {nickname, nickname <> "@" <> domain}

      _ ->
        {query, nil}
    end
  end

  defp notifications_count(nil), do: 0

  defp notifications_count(%User{} = user) do
    user
    |> Notifications.list_for_user(limit: 20, include_offers?: true)
    |> length()
  end
end
