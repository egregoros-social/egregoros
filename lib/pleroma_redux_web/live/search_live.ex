defmodule PleromaReduxWeb.SearchLive do
  use PleromaReduxWeb, :live_view

  alias PleromaRedux.Federation
  alias PleromaRedux.Interactions
  alias PleromaRedux.Media
  alias PleromaRedux.MediaStorage
  alias PleromaRedux.Notifications
  alias PleromaRedux.Objects
  alias PleromaRedux.Publish
  alias PleromaRedux.Relationships
  alias PleromaRedux.User
  alias PleromaRedux.Users
  alias PleromaReduxWeb.ProfilePaths
  alias PleromaReduxWeb.URL
  alias PleromaReduxWeb.ViewModels.Actor, as: ActorVM
  alias PleromaReduxWeb.ViewModels.Status, as: StatusVM

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
        reply_to_ap_id: nil,
        reply_to_handle: nil,
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
         {:ok, remote_user} <- Federation.follow_remote(user, handle) do
      socket =
        socket
        |> put_flash(:info, "Following #{ActorVM.handle(remote_user, remote_user.ap_id)}.")
        |> apply_params(%{"q" => socket.assigns.query})

      {:noreply, socket}
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

  def handle_event("open_reply_modal", %{"in_reply_to" => in_reply_to} = params, socket) do
    in_reply_to = in_reply_to |> to_string() |> String.trim()
    actor_handle = params |> Map.get("actor_handle", "") |> to_string() |> String.trim()

    socket =
      socket
      |> cancel_all_uploads(:reply_media)
      |> assign(
        reply_to_ap_id: in_reply_to,
        reply_to_handle: actor_handle,
        reply_form: Phoenix.Component.to_form(default_reply_params(), as: :reply),
        reply_media_alt: %{},
        reply_options_open?: false,
        reply_cw_open?: false
      )

    {:noreply, socket}
  end

  def handle_event("open_reply_modal", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("close_reply_modal", _params, socket) do
    socket =
      socket
      |> cancel_all_uploads(:reply_media)
      |> assign(
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
        in_reply_to = socket.assigns.reply_to_ap_id

        if is_binary(in_reply_to) and String.trim(in_reply_to) != "" do
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

                  description = media_alt |> Map.get(entry.ref, "") |> to_string() |> String.trim()

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
          {:noreply, put_flash(socket, :error, "Select a post to reply to.")}
        end
    end
  end

  def handle_event("toggle_like", %{"id" => id}, socket) do
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)) do
      _ = Interactions.toggle_like(user, post_id)
      {:noreply, refresh_post(socket, post_id)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle_repost", %{"id" => id}, socket) do
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)) do
      _ = Interactions.toggle_repost(user, post_id)
      {:noreply, refresh_post(socket, post_id)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle_reaction", %{"id" => id, "emoji" => emoji}, socket) do
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)),
         emoji when is_binary(emoji) <- to_string(emoji) do
      _ = Interactions.toggle_reaction(user, post_id, emoji)
      {:noreply, refresh_post(socket, post_id)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delete_post", %{"id" => id}, socket) do
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)),
         {:ok, _delete} <- Interactions.delete_post(user, post_id) do
      {:noreply,
       socket
       |> assign(post_results: Enum.reject(socket.assigns.post_results, &(&1.object.id == post_id)))
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
                <p class="text-xs uppercase tracking-[0.3em] text-slate-500 dark:text-slate-400">
                  Search
                </p>
                <h2 class="mt-2 font-display text-2xl text-slate-900 dark:text-slate-100">
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

          <div data-role="search-results" class="space-y-3">
            <.card
              :if={@remote_handle != nil and @current_user == nil}
              data_role="remote-follow"
              class="p-6"
            >
              <p class="text-sm font-semibold text-slate-900 dark:text-slate-100">
                Follow a remote account
              </p>
              <p class="mt-2 text-sm text-slate-600 dark:text-slate-300">
                Login to follow <span class="font-semibold">{@remote_handle}</span>.
              </p>
              <div class="mt-4 flex flex-wrap items-center gap-2">
                <.button navigate={~p"/login"} size="sm">Login</.button>
                <.button navigate={~p"/register"} variant="secondary" size="sm">Register</.button>
              </div>
            </.card>

            <.card
              :if={@remote_handle != nil and @current_user != nil and !@remote_following?}
              data_role="remote-follow"
              class="p-6"
            >
              <p class="text-sm font-semibold text-slate-900 dark:text-slate-100">
                Follow a remote account
              </p>
              <p class="mt-2 text-sm text-slate-600 dark:text-slate-300">
                Follow <span class="font-semibold">{@remote_handle}</span> via ActivityPub.
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
              <p class="text-sm font-semibold text-slate-900 dark:text-slate-100">
                Remote follow
              </p>
              <p class="mt-2 text-sm text-slate-600 dark:text-slate-300">
                You are following <span class="font-semibold">{@remote_handle}</span>.
              </p>
            </.card>

            <.card :if={@query != "" and @results == []} class="p-6">
              <p class="text-sm text-slate-600 dark:text-slate-300">
                No matching accounts found.
              </p>
            </.card>

            <.card :if={@query == ""} class="p-6">
              <p class="text-sm text-slate-600 dark:text-slate-300">
                Type a query to search for accounts and posts.
              </p>
            </.card>

            <.card :for={user <- @results} class="p-5">
              <.link
                navigate={ProfilePaths.profile_path(user)}
                class="flex items-center gap-4 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400"
              >
                <.avatar
                  name={user.name || user.nickname || user.ap_id}
                  src={URL.absolute(user.avatar_url, user.ap_id)}
                  size="lg"
                />

                <div class="min-w-0 flex-1">
                  <p class="truncate text-sm font-semibold text-slate-900 dark:text-slate-100">
                    {user.name || user.nickname || user.ap_id}
                  </p>
                  <p
                    data-role="search-result-handle"
                    class="truncate text-xs text-slate-500 dark:text-slate-400"
                  >
                  {ActorVM.handle(user, user.ap_id)}
                </p>
              </div>
            </.link>
          </.card>
          </div>

          <section
            data-role="search-post-results"
            :if={@query != ""}
            class="space-y-3"
          >
            <.card class="p-6">
              <p class="text-xs uppercase tracking-[0.3em] text-slate-500 dark:text-slate-400">
                Posts
              </p>
              <h3 class="mt-2 font-display text-xl text-slate-900 dark:text-slate-100">
                Matching notes
              </h3>
            </.card>

            <.card :if={@post_results == []} class="p-6">
              <p class="text-sm text-slate-600 dark:text-slate-300">
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
        reply_to_handle={@reply_to_handle}
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

    results =
      if search_query == "" do
        []
      else
        Users.search(search_query, limit: @page_size)
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
      remote_handle: remote_handle,
      remote_following?: remote_following?,
      post_results: post_results,
      results: results,
      search_form: Phoenix.Component.to_form(%{"q" => q}, as: :search)
    )
  end

  defp post_dom_id(%{object: %{id: id}}) when is_integer(id), do: "search-post-#{id}"
  defp post_dom_id(_post), do: Ecto.UUID.generate()

  defp refresh_post(socket, post_id) when is_integer(post_id) do
    current_user = socket.assigns.current_user

    case Objects.get(post_id) do
      %{type: "Note"} = object ->
        entry = StatusVM.decorate(object, current_user)

        assign(socket,
          post_results:
            Enum.map(socket.assigns.post_results, fn current ->
              if current.object.id == post_id, do: entry, else: current
            end)
        )

      _ ->
        socket
    end
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

  defp truthy?(value) do
    case value do
      true -> true
      1 -> true
      "1" -> true
      "true" -> true
      _ -> false
    end
  end

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
    |> Notifications.list_for_user(limit: 20)
    |> length()
  end
end
