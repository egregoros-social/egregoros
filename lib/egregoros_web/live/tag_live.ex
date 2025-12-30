defmodule EgregorosWeb.TagLive do
  use EgregorosWeb, :live_view

  alias Egregoros.Interactions
  alias Egregoros.Media
  alias Egregoros.MediaStorage
  alias Egregoros.Notifications
  alias Egregoros.Objects
  alias Egregoros.Publish
  alias Egregoros.User
  alias Egregoros.Users
  alias EgregorosWeb.Live.Uploads, as: LiveUploads
  alias EgregorosWeb.MentionAutocomplete
  alias EgregorosWeb.Param
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
       reply_modal_open?: false,
       reply_to_ap_id: nil,
       reply_to_handle: nil,
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
        MentionAutocomplete.suggestions(q, limit: 8)
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

  def handle_event(
        "open_reply_modal",
        %{"in_reply_to" => in_reply_to, "actor_handle" => actor_handle},
        socket
      ) do
    if socket.assigns.current_user do
      in_reply_to = in_reply_to |> to_string() |> String.trim()
      actor_handle = actor_handle |> to_string() |> String.trim()

      if in_reply_to == "" do
        {:noreply, socket}
      else
        reply_params =
          default_reply_params()
          |> Map.put("in_reply_to", in_reply_to)

        socket =
          socket
          |> LiveUploads.cancel_all(:reply_media)
          |> assign(
            reply_modal_open?: true,
            reply_to_ap_id: in_reply_to,
            reply_to_handle: actor_handle,
            reply_form: Phoenix.Component.to_form(reply_params, as: :reply),
            reply_media_alt: %{},
            reply_options_open?: false,
            reply_cw_open?: false
          )

        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_reply_modal", _params, socket) do
    socket =
      socket
      |> LiveUploads.cancel_all(:reply_media)
      |> assign(
        reply_modal_open?: false,
        reply_to_ap_id: nil,
        reply_to_handle: nil,
        reply_form: Phoenix.Component.to_form(default_reply_params(), as: :reply),
        reply_media_alt: %{},
        reply_options_open?: false,
        reply_cw_open?: false
      )

    {:noreply, socket}
  end

  def handle_event("toggle_reply_cw", _params, socket) do
    {:noreply, assign(socket, reply_cw_open?: !socket.assigns.reply_cw_open?)}
  end

  def handle_event("reply_change", %{"reply" => %{} = reply_params}, socket) do
    reply_params = Map.merge(default_reply_params(), reply_params)
    media_alt = Map.get(reply_params, "media_alt", %{})

    reply_options_open? = Param.truthy?(Map.get(reply_params, "ui_options_open"))

    reply_cw_open? =
      socket.assigns.reply_cw_open? ||
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
        in_reply_to =
          case socket.assigns.reply_to_ap_id do
            ap_id when is_binary(ap_id) -> String.trim(ap_id)
            _ -> reply_params |> Map.get("in_reply_to", "") |> to_string() |> String.trim()
          end

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
            socket.assigns.reply_cw_open? ||
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
                         reply_modal_open?: false,
                         reply_to_ap_id: nil,
                         reply_to_handle: nil,
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
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)),
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
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)),
         {:ok, _activity} <- Interactions.toggle_repost(user, post_id) do
      {:noreply, refresh_posts(socket)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to repost.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_reaction", %{"id" => id, "emoji" => emoji}, socket) do
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)),
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
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)),
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
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)),
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
          <.card class="px-5 py-4">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <.link
                navigate={timeline_href(@current_user)}
                class="inline-flex items-center gap-2 rounded-full border border-slate-200/80 bg-white/70 px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-slate-700 transition hover:-translate-y-0.5 hover:bg-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:hover:bg-slate-950"
                aria-label="Back to timeline"
              >
                <.icon name="hero-arrow-left" class="size-4" /> Timeline
              </.link>

              <div class="text-right">
                <p
                  data-role="tag-title"
                  class="font-display text-lg text-slate-900 dark:text-slate-100"
                >
                  #{to_string(@tag)}
                </p>
                <p class="mt-1 text-xs uppercase tracking-[0.3em] text-slate-500 dark:text-slate-400">
                  Hashtag
                </p>
              </div>
            </div>
          </.card>

          <div class="space-y-4">
            <div
              :if={@posts == []}
              class="rounded-3xl border border-slate-200/80 bg-white/70 p-6 text-sm text-slate-600 shadow-sm shadow-slate-200/20 dark:border-slate-700/70 dark:bg-slate-950/50 dark:text-slate-300 dark:shadow-slate-900/30"
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
              phx-click="load_more_posts"
              phx-disable-with="Loading..."
              aria-label="Load more posts"
              variant="secondary"
            >
              <.icon name="hero-chevron-down" class="size-4" /> Load more
            </.button>
          </div>
        </section>
      </AppShell.app_shell>

      <ReplyModal.reply_modal
        :if={@current_user}
        form={@reply_form}
        upload={@uploads.reply_media}
        media_alt={@reply_media_alt}
        reply_to_handle={@reply_to_handle}
        mention_suggestions={@mention_suggestions}
        options_open?={@reply_options_open?}
        cw_open?={@reply_cw_open?}
        open={@reply_modal_open?}
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
      "ui_options_open" => "false",
      "media_alt" => %{}
    }
  end

  defp notifications_count(nil), do: 0

  defp notifications_count(%User{} = user) do
    user
    |> Notifications.list_for_user(limit: @page_size)
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
      %{id: id} when is_integer(id) -> id
      _ -> nil
    end
  end

  defp timeline_href(%{id: _}), do: ~p"/?timeline=home"
  defp timeline_href(_user), do: ~p"/?timeline=public"
end
