defmodule EgregorosWeb.BookmarksLive do
  use EgregorosWeb, :live_view

  import Ecto.Query, only: [from: 2]

  alias Egregoros.Badges
  alias Egregoros.Interactions
  alias Egregoros.Media
  alias Egregoros.MediaStorage
  alias Egregoros.Notifications
  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Publish
  alias Egregoros.Relationship
  alias Egregoros.Repo
  alias Egregoros.User
  alias Egregoros.Users
  alias EgregorosWeb.MentionAutocomplete
  alias EgregorosWeb.Param
  alias EgregorosWeb.ViewModels.Actor, as: ActorVM
  alias EgregorosWeb.ViewModels.Status, as: StatusVM

  @page_size 20

  @impl true
  def mount(_params, session, socket) do
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
        kind: kind_for_action(socket.assigns.live_action),
        relationship_type: relationship_type(kind_for_action(socket.assigns.live_action)),
        saved_cursor: nil,
        saved_end?: true,
        page_kicker: nil,
        page_title: nil,
        empty_message: nil,
        mention_suggestions: %{},
        reply_form: Phoenix.Component.to_form(default_reply_params(), as: :reply),
        reply_media_alt: %{},
        reply_options_open?: false,
        reply_cw_open?: false
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

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    kind = kind_for_action(socket.assigns.live_action)
    {:noreply, apply_kind(socket, kind)}
  end

  @impl true
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

      socket =
        case socket.assigns.kind do
          :favourites -> refresh_or_drop_favourite(socket, post_id)
          _ -> refresh_post(socket, post_id)
        end

      {:noreply, socket}
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

      {:noreply, refresh_post(socket, post_id)}
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
         true <- flake_id?(post_id),
         emoji when is_binary(emoji) <- to_string(emoji) do
      _ = Interactions.toggle_reaction(user, post_id, emoji)
      {:noreply, refresh_post(socket, post_id)}
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
         true <- flake_id?(post_id),
         {:ok, result} <- Interactions.toggle_bookmark(user, post_id) do
      socket =
        case {socket.assigns.kind, result} do
          {:bookmarks, :unbookmarked} ->
            stream_delete(socket, :saved_posts, %{object: %{id: post_id}})

          _ ->
            refresh_post(socket, post_id)
        end

      {:noreply, socket}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to bookmark posts.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_post", %{"id" => id}, socket) do
    post_id = id |> to_string() |> String.trim()

    with %User{} = user <- socket.assigns.current_user,
         true <- flake_id?(post_id),
         {:ok, _delete} <- Interactions.delete_post(user, post_id) do
      {:noreply,
       socket
       |> put_flash(:info, "Post deleted.")
       |> stream_delete(:saved_posts, %{object: %{id: post_id}})}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to delete posts.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not delete post.")}
    end
  end

  def handle_event("load_more", _params, socket) do
    cursor = socket.assigns.saved_cursor

    cond do
      socket.assigns.saved_end? ->
        {:noreply, socket}

      is_nil(cursor) ->
        {:noreply, assign(socket, saved_end?: true)}

      true ->
        saved =
          list_saved_posts(socket.assigns.current_user, socket.assigns.relationship_type,
            limit: @page_size,
            max_id: cursor
          )

        socket =
          if saved == [] do
            assign(socket, saved_end?: true)
          else
            posts = saved |> Enum.map(fn {_cursor_id, object} -> object end)
            new_cursor = saved_cursor(saved)
            saved_end? = length(saved) < @page_size
            current_user = socket.assigns.current_user

            socket =
              Enum.reduce(StatusVM.decorate_many(posts, current_user), socket, fn entry, socket ->
                stream_insert(socket, :saved_posts, entry, at: -1)
              end)

            assign(socket, saved_cursor: new_cursor, saved_end?: saved_end?)
          end

        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <AppShell.app_shell
        id="bookmarks-shell"
        nav_id="bookmarks-nav"
        main_id="bookmarks-main"
        active={:bookmarks}
        current_user={@current_user}
        notifications_count={@notifications_count}
      >
        <section class="space-y-4">
          <.card class="p-6">
            <div class="flex items-center justify-between gap-4">
              <div class="min-w-0">
                <p class="text-xs font-bold uppercase tracking-wide text-[color:var(--text-muted)]">
                  {@page_kicker}
                </p>
                <h2 class="mt-2 truncate text-2xl font-bold text-[color:var(--text-primary)]">
                  {@page_title}
                </h2>
              </div>

              <div class="flex items-center gap-2">
                <.link
                  patch={~p"/bookmarks"}
                  class={[
                    "border-2 px-4 py-2 text-xs font-bold uppercase tracking-wide transition",
                    @kind == :bookmarks &&
                      "border-[color:var(--border-default)] bg-[color:var(--text-primary)] text-[color:var(--bg-base)]",
                    @kind != :bookmarks &&
                      "border-[color:var(--border-default)] bg-[color:var(--bg-base)] text-[color:var(--text-secondary)] hover:bg-[color:var(--text-primary)] hover:text-[color:var(--bg-base)]"
                  ]}
                  aria-label="View bookmarks"
                >
                  Bookmarks
                </.link>

                <.link
                  patch={~p"/favourites"}
                  class={[
                    "border-2 px-4 py-2 text-xs font-bold uppercase tracking-wide transition",
                    @kind == :favourites &&
                      "border-[color:var(--border-default)] bg-[color:var(--text-primary)] text-[color:var(--bg-base)]",
                    @kind != :favourites &&
                      "border-[color:var(--border-default)] bg-[color:var(--bg-base)] text-[color:var(--text-secondary)] hover:bg-[color:var(--text-primary)] hover:text-[color:var(--bg-base)]"
                  ]}
                  aria-label="View favourites"
                >
                  Favourites
                </.link>
              </div>
            </div>
          </.card>

          <%= if @current_user do %>
            <div id="bookmarks-list" phx-update="stream" class="space-y-4">
              <div
                id="bookmarks-empty"
                class="hidden only:block border-2 border-[color:var(--border-default)] bg-[color:var(--bg-subtle)] p-6 text-sm text-[color:var(--text-secondary)]"
              >
                {@empty_message}
              </div>

              <StatusCard.status_card
                :for={{id, entry} <- @streams.saved_posts}
                id={id}
                entry={entry}
                current_user={@current_user}
                reply_mode={:modal}
              />
            </div>

            <div :if={!@saved_end?} class="flex justify-center py-2">
              <.button
                data-role="bookmarks-load-more"
                phx-click={JS.show(to: "#bookmarks-loading-more") |> JS.push("load_more")}
                phx-disable-with="Loading..."
                aria-label="Load more saved posts"
                variant="secondary"
              >
                <.icon name="hero-chevron-down" class="size-4" /> Load more
              </.button>
            </div>

            <div
              :if={!@saved_end?}
              id="bookmarks-loading-more"
              data-role="bookmarks-loading-more"
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
                data-role="bookmarks-auth-required"
                class="text-sm text-[color:var(--text-secondary)]"
              >
                Sign in to view saved posts.
              </p>
              <div class="mt-4 flex flex-wrap items-center gap-2">
                <.button navigate={~p"/login"} size="sm">Login</.button>
                <.button navigate={~p"/register"} size="sm" variant="secondary">Register</.button>
              </div>
            </.card>
          <% end %>
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

  defp refresh_post(socket, post_id) when is_binary(post_id) do
    current_user = socket.assigns.current_user

    case Objects.get(post_id) do
      %{type: type} = object when type in ["Note", "Question", "VerifiableCredential"] ->
        if Objects.visible_to?(object, current_user) do
          stream_insert(socket, :saved_posts, StatusVM.decorate(object, current_user))
        else
          stream_delete(socket, :saved_posts, %{object: %{id: post_id}})
        end

      _ ->
        socket
    end
  end

  defp refresh_or_drop_favourite(socket, post_id) when is_binary(post_id) do
    current_user = socket.assigns.current_user

    case Objects.get(post_id) do
      %{type: type} = object when type in ["Note", "Question", "VerifiableCredential"] ->
        if Objects.visible_to?(object, current_user) do
          entry = StatusVM.decorate(object, current_user)

          if entry.liked? do
            stream_insert(socket, :saved_posts, entry)
          else
            stream_delete(socket, :saved_posts, %{object: %{id: post_id}})
          end
        else
          stream_delete(socket, :saved_posts, %{object: %{id: post_id}})
        end

      _ ->
        socket
    end
  end

  defp apply_kind(socket, kind) do
    relationship_type = relationship_type(kind)

    %{page_kicker: page_kicker, page_title: page_title, empty_message: empty_message} =
      labels(kind)

    saved = list_saved_posts(socket.assigns.current_user, relationship_type, limit: @page_size)
    posts = saved |> Enum.map(fn {_cursor_id, object} -> object end)
    cursor = saved_cursor(saved)

    socket
    |> assign(
      kind: kind,
      relationship_type: relationship_type,
      saved_cursor: cursor,
      saved_end?: length(saved) < @page_size,
      page_kicker: page_kicker,
      page_title: page_title,
      empty_message: empty_message
    )
    |> stream(:saved_posts, StatusVM.decorate_many(posts, socket.assigns.current_user),
      reset: true,
      dom_id: &post_dom_id/1
    )
  end

  defp labels(:favourites) do
    %{
      page_kicker: "Favourites",
      page_title: "Liked posts",
      empty_message: "No favourites yet."
    }
  end

  defp labels(_kind) do
    %{
      page_kicker: "Bookmarks",
      page_title: "Saved posts",
      empty_message: "No bookmarks yet."
    }
  end

  defp relationship_type(:favourites), do: "Like"
  defp relationship_type(_kind), do: "Bookmark"

  defp kind_for_action(:favourites), do: :favourites
  defp kind_for_action(_live_action), do: :bookmarks

  defp list_saved_posts(nil, _relationship_type, _opts), do: []

  defp list_saved_posts(%User{} = user, relationship_type, opts)
       when is_binary(relationship_type) and is_list(opts) do
    limit = opts |> Keyword.get(:limit, @page_size) |> normalize_limit()
    max_id = opts |> Keyword.get(:max_id) |> normalize_id()

    from(r in Relationship,
      join: o in Object,
      on: o.ap_id == r.object,
      where: r.type == ^relationship_type and r.actor == ^user.ap_id and o.type == "Note",
      order_by: [desc: r.id],
      limit: ^limit,
      select: {r.id, o}
    )
    |> maybe_where_max_id(max_id)
    |> Repo.all()
  end

  defp maybe_where_max_id(query, max_id) when is_binary(max_id) do
    max_id = String.trim(max_id)

    if flake_id?(max_id) do
      from([r, _o] in query, where: r.id < ^max_id)
    else
      query
    end
  end

  defp maybe_where_max_id(query, _max_id), do: query

  defp saved_cursor(saved) when is_list(saved) do
    case List.last(saved) do
      {cursor_id, _object} when is_binary(cursor_id) -> cursor_id
      _ -> nil
    end
  end

  defp post_dom_id(%{object: %{id: id}}) when is_binary(id), do: "post-#{id}"
  defp post_dom_id(_post), do: Ecto.UUID.generate()

  defp normalize_limit(limit) when is_integer(limit) do
    limit
    |> max(1)
    |> min(40)
  end

  defp normalize_limit(_), do: @page_size

  defp normalize_id(nil), do: nil

  defp normalize_id(id) when is_binary(id) do
    id = String.trim(id)
    if flake_id?(id), do: id, else: nil
  end

  defp normalize_id(_), do: nil

  defp flake_id?(id) when is_binary(id) do
    id = String.trim(id)
    byte_size(id) == 18 and FlakeId.flake_id?(id)
  end

  defp flake_id?(_id), do: false

  defp notifications_count(nil), do: 0

  defp notifications_count(%User{} = user) do
    user
    |> Notifications.list_for_user(limit: 20, include_offers?: true)
    |> length()
  end

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
end
