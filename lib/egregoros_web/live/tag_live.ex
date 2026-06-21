defmodule EgregorosWeb.TagLive do
  use EgregorosWeb, :live_view

  alias Egregoros.Badges
  alias Egregoros.Interactions
  alias Egregoros.Media
  alias Egregoros.MediaStorage
  alias Egregoros.Notifications
  alias Egregoros.Objects
  alias Egregoros.Publish
  alias Egregoros.User
  alias Egregoros.Users
  alias EgregorosWeb.MentionAutocomplete
  alias EgregorosWeb.Param
  alias EgregorosWeb.ViewModels.Actor, as: ActorVM
  alias EgregorosWeb.ViewModels.Status, as: StatusVM

  @page_size 20

  @impl true
  def mount(%{"tag" => tag}, session, socket) do
    current_user =
      case Map.get(session, "user_id") do
        nil -> nil
        id -> Users.get(id)
      end

    tag =
      tag
      |> to_string()
      |> String.trim()
      |> String.trim_leading("#")

    objects = Objects.list_notes_by_hashtag(tag, limit: @page_size)

    reply_form = Phoenix.Component.to_form(default_reply_params(), as: :reply)

    {:ok,
     socket
     |> assign(
       current_user: current_user,
       notifications_count: notifications_count(current_user),
       mention_suggestions: %{},
       tag: tag,
       posts: StatusVM.decorate_many(objects, current_user),
       reply_form: reply_form,
       reply_media_alt: %{},
       reply_options_open?: false,
       reply_cw_open?: false,
       posts_cursor: posts_cursor(objects),
       posts_end?: length(objects) < @page_size
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
     )}
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
         true <- flake_id?(post_id),
         {:ok, _activity} <- Interactions.toggle_like(user, post_id) do
      {:noreply, refresh_posts(socket)}
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
         true <- flake_id?(post_id),
         {:ok, _activity} <- Interactions.toggle_repost(user, post_id) do
      socket =
        case Badges.badge_share_flash_message(user, post_id) do
          message when is_binary(message) and message != "" ->
            put_flash(socket, :info, message)

          _ ->
            socket
        end

      {:noreply, refresh_posts(socket)}
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
         emoji when is_binary(emoji) <- to_string(emoji),
         {:ok, _activity} <- Interactions.toggle_reaction(user, post_id, emoji) do
      {:noreply, refresh_posts(socket)}
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
         {:ok, _} <- Interactions.toggle_bookmark(user, post_id) do
      {:noreply, refresh_posts(socket)}
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
      posts =
        socket.assigns.posts
        |> Enum.reject(fn entry ->
          match?(%{object: %{id: ^post_id}}, entry)
        end)

      cursor =
        posts
        |> Enum.map(& &1.object)
        |> posts_cursor()

      {:noreply,
       socket
       |> put_flash(:info, "Post deleted.")
       |> assign(posts: posts, posts_cursor: cursor)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to delete posts.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not delete post.")}
    end
  end

  def handle_event("load_more_posts", _params, socket) do
    cursor = socket.assigns.posts_cursor

    cond do
      socket.assigns.posts_end? ->
        {:noreply, socket}

      is_nil(cursor) ->
        {:noreply, assign(socket, posts_end?: true)}

      true ->
        objects =
          Objects.list_notes_by_hashtag(socket.assigns.tag, limit: @page_size, max_id: cursor)

        socket =
          if objects == [] do
            assign(socket, posts_end?: true)
          else
            new_cursor = posts_cursor(objects)
            posts_end? = length(objects) < @page_size

            posts =
              socket.assigns.posts
              |> Kernel.++(StatusVM.decorate_many(objects, socket.assigns.current_user))
              |> Enum.uniq_by(& &1.object.id)

            assign(socket, posts: posts, posts_cursor: new_cursor, posts_end?: posts_end?)
          end

        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <AppShell.app_shell
        id="tag-shell"
        nav_id="tag-nav"
        main_id="tag-main"
        active={:timeline}
        current_user={@current_user}
        notifications_count={@notifications_count}
      >
        <section class="space-y-4">
          <.card class="px-4 py-3">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <.link
                navigate={timeline_href(@current_user)}
                class="inline-flex items-center gap-2 border-2 border-[color:var(--border-default)] bg-[color:var(--bg-base)] px-4 py-2 text-xs font-bold uppercase tracking-wide text-[color:var(--text-secondary)] transition hover:bg-[color:var(--text-primary)] hover:text-[color:var(--bg-base)] focus-visible:outline-none focus-brutal"
                aria-label="Back to timeline"
              >
                <.icon name="hero-arrow-left" class="size-4" /> Timeline
              </.link>

              <div class="text-right">
                <p
                  data-role="tag-title"
                  class="text-lg font-bold text-[color:var(--text-primary)]"
                >
                  #{to_string(@tag)}
                </p>
                <p class="mt-1 font-mono text-xs uppercase text-[color:var(--text-muted)]">
                  Hashtag
                </p>
              </div>
            </div>
          </.card>

          <div class="space-y-4">
            <div
              :if={@posts == []}
              class="border-2 border-[color:var(--border-default)] bg-[color:var(--bg-subtle)] p-6 text-sm text-[color:var(--text-secondary)]"
            >
              No posts yet.
            </div>

            <StatusCard.status_card
              :for={entry <- @posts}
              id={"post-#{entry.object.id}"}
              entry={entry}
              current_user={@current_user}
              reply_mode={:modal}
            />
          </div>

          <div :if={!@posts_end?} class="flex justify-center py-2">
            <.button
              data-role="tag-load-more"
              phx-click={JS.show(to: "#tag-loading-more") |> JS.push("load_more_posts")}
              phx-disable-with="Loading..."
              aria-label="Load more posts"
              variant="secondary"
            >
              <.icon name="hero-chevron-down" class="size-4" /> Load more
            </.button>
          </div>

          <div
            :if={!@posts_end?}
            id="tag-loading-more"
            data-role="tag-loading-more"
            class="hidden space-y-4"
            aria-hidden="true"
          >
            <.skeleton_status_card
              :for={_ <- 1..2}
              class="border-2 border-[color:var(--border-default)]"
            />
          </div>
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

  defp notifications_count(nil), do: 0

  defp notifications_count(%User{} = user) do
    user
    |> Notifications.list_for_user(limit: @page_size, include_offers?: true)
    |> length()
  end

  defp refresh_posts(socket) do
    current_user = socket.assigns.current_user

    posts =
      Enum.map(socket.assigns.posts, fn entry ->
        StatusVM.decorate(entry.object, current_user)
      end)

    assign(socket, posts: posts)
  end

  defp posts_cursor([]), do: nil

  defp posts_cursor(posts) when is_list(posts) do
    case List.last(posts) do
      %{id: id} when is_binary(id) -> id
      _ -> nil
    end
  end

  defp flake_id?(id) when is_binary(id) do
    id = String.trim(id)
    byte_size(id) == 18 and FlakeId.flake_id?(id)
  end

  defp flake_id?(_id), do: false

  defp timeline_href(%{id: _}), do: ~p"/?timeline=home"
  defp timeline_href(_user), do: ~p"/?timeline=public"
end
