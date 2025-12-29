defmodule EgregorosWeb.StatusLive do
  use EgregorosWeb, :live_view

  alias Egregoros.Domain
  alias Egregoros.Interactions
  alias Egregoros.Media
  alias Egregoros.MediaStorage
  alias Egregoros.Notifications
  alias Egregoros.Objects
  alias Egregoros.Publish
  alias Egregoros.User
  alias Egregoros.Users
  alias EgregorosWeb.MentionAutocomplete
  alias EgregorosWeb.Endpoint
  alias EgregorosWeb.ProfilePaths
  alias EgregorosWeb.ViewModels.Status, as: StatusVM

  @reply_max_chars 5000

  @impl true
  def mount(%{"nickname" => nickname, "uuid" => uuid} = params, session, socket) do
    current_user =
      case Map.get(session, "user_id") do
        nil -> nil
        id -> Users.get(id)
      end

    object =
      case object_for_uuid_param(uuid) do
        %Egregoros.Object{} = object ->
          if Objects.visible_to?(object, current_user), do: object, else: nil

        _ ->
          nil
      end

    reply_modal_open? = truthy?(Map.get(params, "reply")) and not is_nil(current_user)

    {status_entry, ancestor_entries, descendant_entries} =
      case object do
        %{type: "Note"} = note ->
          status_entry = StatusVM.decorate(note, current_user)

          ancestors =
            note
            |> Objects.thread_ancestors()
            |> Enum.filter(&Objects.visible_to?(&1, current_user))
            |> StatusVM.decorate_many(current_user)

          descendants = decorate_descendants(note, current_user)
          {status_entry, ancestors, descendants}

        _ ->
          {nil, [], []}
      end

    reply_to_handle =
      if reply_modal_open? and status_entry do
        status_entry.actor.handle
      else
        nil
      end

    reply_to_ap_id =
      if reply_modal_open? and status_entry do
        status_entry.object.ap_id
      else
        nil
      end

    reply_params =
      if reply_modal_open? and is_binary(reply_to_ap_id) do
        default_reply_params() |> Map.put("in_reply_to", reply_to_ap_id)
      else
        default_reply_params()
      end

    reply_form = Phoenix.Component.to_form(reply_params, as: :reply)

    socket =
      socket
      |> assign(
        current_user: current_user,
        notifications_count: notifications_count(current_user),
        nickname: nickname,
        uuid: uuid,
        status: status_entry,
        ancestors: ancestor_entries,
        descendants: descendant_entries,
        reply_modal_open?: reply_modal_open?,
        reply_to_ap_id: reply_to_ap_id,
        reply_to_handle: reply_to_handle,
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
          |> cancel_all_uploads(:reply_media)
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

  def handle_event("cancel_reply_media", %{"ref" => ref}, socket) do
    {:noreply,
     socket
     |> cancel_upload(:reply_media, ref)
     |> assign(:reply_media_alt, Map.delete(socket.assigns.reply_media_alt, ref))}
  end

  def handle_event("toggle_like", %{"id" => id}, socket) do
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)) do
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
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)) do
      _ = Interactions.toggle_repost(user, post_id)

      {:noreply, refresh_thread(socket)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to repost.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_reaction", %{"id" => id, "emoji" => emoji}, socket) do
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)) do
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
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)) do
      _ = Interactions.toggle_bookmark(user, post_id)

      {:noreply, refresh_thread(socket)}
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
      socket =
        case socket.assigns.status do
          %{object: %{id: ^post_id}} ->
            socket
            |> put_flash(:info, "Post deleted.")
            |> push_navigate(to: timeline_href(user))

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

  def handle_event("close_reply_modal", _params, socket) do
    socket =
      socket
      |> cancel_all_uploads(:reply_media)
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

    reply_options_open? = truthy?(Map.get(reply_params, "ui_options_open"))

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

  def handle_event("create_reply", %{"reply" => %{} = reply_params}, socket) do
    reply_params = Map.merge(default_reply_params(), reply_params)
    content = reply_params |> Map.get("content", "") |> to_string()
    media_alt = Map.get(reply_params, "media_alt", %{})
    visibility = Map.get(reply_params, "visibility", "public")
    spoiler_text = Map.get(reply_params, "spoiler_text")
    sensitive = Map.get(reply_params, "sensitive")
    language = Map.get(reply_params, "language")

    reply_options_open? = truthy?(Map.get(reply_params, "ui_options_open"))

    reply_cw_open? =
      socket.assigns.reply_cw_open? ||
        reply_params |> Map.get("spoiler_text", "") |> to_string() |> String.trim() != ""

    in_reply_to =
      case socket.assigns.reply_to_ap_id do
        ap_id when is_binary(ap_id) -> String.trim(ap_id)
        _ -> reply_params |> Map.get("in_reply_to", "") |> to_string() |> String.trim()
      end

    with %User{} = user <- socket.assigns.current_user,
         true <- in_reply_to != "" do
      upload = socket.assigns.uploads.reply_media

      cond do
        Enum.any?(upload.entries, &(!&1.done?)) ->
          {:noreply,
           socket
           |> put_flash(:error, "Wait for attachments to finish uploading.")
           |> assign(
             reply_modal_open?: true,
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
             reply_modal_open?: true,
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
                 reply_modal_open?: true,
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
                     reply_modal_open?: false,
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
                     reply_modal_open?: true,
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
                     reply_modal_open?: true,
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
                     reply_modal_open?: true,
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
            <div class="flex flex-wrap items-center justify-between gap-3 rounded-3xl border border-white/80 bg-white/80 px-5 py-4 shadow-lg shadow-slate-200/20 backdrop-blur dark:border-slate-700/60 dark:bg-slate-900/70 dark:shadow-slate-900/40">
              <.link
                navigate={timeline_href(@current_user)}
                class="inline-flex items-center gap-2 rounded-full border border-slate-200/80 bg-white/70 px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-slate-700 transition hover:-translate-y-0.5 hover:bg-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:hover:bg-slate-950"
                aria-label="Back to timeline"
              >
                <.icon name="hero-arrow-left" class="size-4" /> Timeline
              </.link>

              <div class="text-right">
                <p class="font-display text-lg text-slate-900 dark:text-slate-100">Post</p>
                <p class="mt-1 text-xs uppercase tracking-[0.3em] text-slate-500 dark:text-slate-400">
                  {if @status.object.local, do: "Local status", else: "Remote status"}
                </p>
              </div>
            </div>

            <div class="space-y-6" data-role="status-thread">
              <div :if={@ancestors != []} data-role="thread-ancestors" class="space-y-4">
                <div class="flex items-center justify-between gap-3 px-1">
                  <p class="text-xs font-semibold uppercase tracking-[0.3em] text-slate-500 dark:text-slate-400">
                    Context
                  </p>
                  <span class="text-xs font-semibold text-slate-500 dark:text-slate-400">
                    {length(@ancestors)}
                  </span>
                </div>

                <StatusCard.status_card
                  :for={entry <- @ancestors}
                  id={"post-#{entry.object.id}"}
                  entry={entry}
                  current_user={@current_user}
                  reply_mode={:modal}
                />
              </div>

              <div class="rounded-3xl ring-2 ring-slate-900/10 dark:ring-white/10">
                <StatusCard.status_card
                  id={"post-#{@status.object.id}"}
                  entry={@status}
                  current_user={@current_user}
                  reply_mode={:modal}
                />
              </div>

              <div data-role="thread-replies" class="space-y-4">
                <div class="flex items-center justify-between gap-3 px-1">
                  <p class="text-xs font-semibold uppercase tracking-[0.3em] text-slate-500 dark:text-slate-400">
                    Replies
                  </p>
                  <span class="text-xs font-semibold text-slate-500 dark:text-slate-400">
                    {length(@descendants)}
                  </span>
                </div>

                <div
                  :if={@descendants == []}
                  data-role="thread-replies-empty"
                  class="rounded-3xl border border-slate-200/80 bg-white/70 p-6 text-sm text-slate-600 shadow-sm shadow-slate-200/20 dark:border-slate-700/70 dark:bg-slate-950/50 dark:text-slate-300 dark:shadow-slate-900/30"
                >
                  No replies yet.
                </div>

                <div
                  :for={%{entry: entry, depth: depth} <- @descendants}
                  data-role="thread-descendant"
                  data-depth={depth}
                  style={"margin-left: #{thread_indent(depth)}px"}
                  class={[
                    depth > 1 && "border-l border-slate-200/60 pl-4 dark:border-slate-700/60"
                  ]}
                >
                  <StatusCard.status_card
                    id={"post-#{entry.object.id}"}
                    entry={entry}
                    current_user={@current_user}
                    reply_mode={:modal}
                  />
                </div>
              </div>
            </div>
          </section>
        <% else %>
          <section class="rounded-3xl border border-slate-200/80 bg-white/70 p-8 text-center shadow-sm shadow-slate-200/20 dark:border-slate-700/70 dark:bg-slate-950/50 dark:shadow-slate-900/30">
            <p class="font-display text-xl text-slate-900 dark:text-slate-100">Post not found</p>
            <p class="mt-3 text-sm text-slate-600 dark:text-slate-300">
              This status may have been deleted or was never fetched by this instance.
            </p>
            <div class="mt-6 flex justify-center">
              <.link
                navigate={timeline_href(@current_user)}
                class="inline-flex items-center gap-2 rounded-full bg-slate-900 px-6 py-3 text-sm font-semibold text-white shadow-lg shadow-slate-900/20 transition hover:-translate-y-0.5 hover:bg-slate-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-white"
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
        mention_suggestions={@mention_suggestions}
        max_chars={reply_max_chars()}
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

  defp object_for_uuid_param(uuid) when is_binary(uuid) do
    uuid = String.trim(uuid)

    if uuid == "" do
      nil
    else
      case Integer.parse(uuid) do
        {id, ""} ->
          Objects.get(id)

        _ ->
          ap_id = Endpoint.url() <> "/objects/" <> uuid
          Objects.get_by_ap_id(ap_id)
      end
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
    |> Notifications.list_for_user(limit: 20)
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

  defp cancel_all_uploads(socket, upload_name) when is_atom(upload_name) do
    case socket.assigns.uploads |> Map.get(upload_name) do
      %{entries: entries} when is_list(entries) ->
        Enum.reduce(entries, socket, fn entry, socket ->
          cancel_upload(socket, upload_name, entry.ref)
        end)

      _ ->
        socket
    end
  end

  defp refresh_thread(socket) do
    current_user = socket.assigns.current_user

    case socket.assigns.status do
      %{object: %{type: "Note"} = note} ->
        socket
        |> assign(
          status: StatusVM.decorate(note, current_user),
          ancestors:
            note
            |> Objects.thread_ancestors()
            |> Enum.filter(&Objects.visible_to?(&1, current_user))
            |> StatusVM.decorate_many(current_user),
          descendants: decorate_descendants(note, current_user)
        )

      _ ->
        socket
    end
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

  defp in_reply_to_ap_id(value) when is_binary(value), do: value
  defp in_reply_to_ap_id(%{"id" => id}) when is_binary(id), do: id
  defp in_reply_to_ap_id(_), do: nil

  defp thread_indent(depth) when is_integer(depth) do
    depth
    |> Kernel.-(1)
    |> max(0)
    |> min(5)
    |> Kernel.*(24)
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
      "ui_options_open" => "false",
      "media_alt" => %{}
    }
  end

  defp truthy?(value) do
    case value do
      true -> true
      1 -> true
      "1" -> true
      "true" -> true
      _ -> false
    end
  end

  defp timeline_href(%{id: _}), do: ~p"/?timeline=home"
  defp timeline_href(_user), do: ~p"/?timeline=public"
end
