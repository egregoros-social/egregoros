defmodule EgregorosWeb.ProfileLive do
  use EgregorosWeb, :live_view

  alias Egregoros.Activities.Follow
  alias Egregoros.Activities.Undo
  alias Egregoros.Interactions
  alias Egregoros.HTML
  alias Egregoros.Media
  alias Egregoros.MediaStorage
  alias Egregoros.Notifications
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Publish
  alias Egregoros.Relationships
  alias Egregoros.User
  alias Egregoros.Users
  alias EgregorosWeb.Live.Uploads, as: LiveUploads
  alias EgregorosWeb.MentionAutocomplete
  alias EgregorosWeb.Param
  alias EgregorosWeb.ProfilePaths
  alias EgregorosWeb.URL
  alias EgregorosWeb.ViewModels.Actor, as: ActorVM
  alias EgregorosWeb.ViewModels.Status, as: StatusVM

  @page_size 20

  @impl true
  def mount(%{"nickname" => handle}, session, socket) do
    current_user =
      case Map.get(session, "user_id") do
        nil -> nil
        id -> Users.get(id)
      end

    profile_user =
      handle
      |> to_string()
      |> String.trim()
      |> Users.get_by_handle()

    profile_handle =
      case profile_user do
        %User{} = user -> ActorVM.handle(user, user.ap_id)
        _ -> nil
      end

    posts =
      case profile_user do
        %User{} = user ->
          Objects.list_visible_notes_by_actor(user.ap_id, current_user, limit: @page_size)

        _ ->
          []
      end

    follow_relationship =
      follow_relationship(current_user, profile_user)

    follow_request_relationship =
      follow_request_relationship(current_user, profile_user)

    block_relationship =
      relationship_for("Block", current_user, profile_user)

    mute_relationship =
      relationship_for("Mute", current_user, profile_user)

    follows_you? =
      follows_you?(current_user, profile_user)

    reply_form = Phoenix.Component.to_form(default_reply_params(), as: :reply)

    profile_bio_html =
      case profile_user do
        %User{} = user ->
          user.bio
          |> HTML.to_safe_html(format: if(user.local, do: :text, else: :html))
          |> Phoenix.HTML.raw()

        _ ->
          nil
      end

    {:ok,
     socket
     |> assign(
       current_user: current_user,
       profile_user: profile_user,
       profile_handle: profile_handle,
       profile_bio_html: profile_bio_html,
       notifications_count: notifications_count(current_user),
       follow_relationship: follow_relationship,
       follow_request_relationship: follow_request_relationship,
       block_relationship: block_relationship,
       mute_relationship: mute_relationship,
       follows_you?: follows_you?,
       mention_suggestions: %{},
       reply_modal_open?: false,
       reply_to_ap_id: nil,
       reply_to_handle: nil,
       reply_form: reply_form,
       reply_media_alt: %{},
       reply_options_open?: false,
       reply_cw_open?: false,
       posts_count: count_posts(profile_user, current_user),
       followers_count: count_followers(profile_user),
       following_count: count_following(profile_user),
       posts_cursor: posts_cursor(posts),
       posts_end?: length(posts) < @page_size
     )
     |> stream(:posts, StatusVM.decorate_many(posts, current_user), dom_id: &post_dom_id/1)
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

  def handle_event("follow", _params, socket) do
    with %User{} = viewer <- socket.assigns.current_user,
         %User{} = profile_user <- socket.assigns.profile_user,
         true <- viewer.id != profile_user.id,
         nil <- socket.assigns.block_relationship,
         nil <- Relationships.get_by_type_actor_object("Follow", viewer.ap_id, profile_user.ap_id),
         {:ok, _follow} <- Pipeline.ingest(Follow.build(viewer, profile_user), local: true) do
      relationship = follow_relationship(viewer, profile_user)
      follow_request = follow_request_relationship(viewer, profile_user)

      message =
        cond do
          relationship != nil -> "Following #{profile_user.nickname}."
          follow_request != nil -> "Follow request sent to #{profile_user.nickname}."
          true -> "Followed #{profile_user.nickname}."
        end

      {:noreply,
       socket
       |> put_flash(:info, message)
       |> assign(
         follow_relationship: relationship,
         follow_request_relationship: follow_request,
         followers_count: count_followers(profile_user)
       )}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to follow people.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("mute", _params, socket) do
    with %User{} = viewer <- socket.assigns.current_user,
         %User{} = profile_user <- socket.assigns.profile_user,
         true <- viewer.id != profile_user.id,
         {:ok, %{} = relationship} <-
           Relationships.upsert_relationship(%{
             type: "Mute",
             actor: viewer.ap_id,
             object: profile_user.ap_id,
             activity_ap_id: nil
           }) do
      {:noreply,
       socket
       |> put_flash(:info, "Muted #{profile_user.nickname}.")
       |> assign(mute_relationship: relationship)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to mute people.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("unmute", _params, socket) do
    with %User{} = viewer <- socket.assigns.current_user,
         %User{} = profile_user <- socket.assigns.profile_user,
         true <- viewer.id != profile_user.id do
      Relationships.delete_by_type_actor_object("Mute", viewer.ap_id, profile_user.ap_id)

      {:noreply,
       socket
       |> put_flash(:info, "Unmuted #{profile_user.nickname}.")
       |> assign(mute_relationship: nil)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to unmute people.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("block", _params, socket) do
    with %User{} = viewer <- socket.assigns.current_user,
         %User{} = profile_user <- socket.assigns.profile_user,
         true <- viewer.id != profile_user.id,
         {:ok, %{} = relationship} <-
           Relationships.upsert_relationship(%{
             type: "Block",
             actor: viewer.ap_id,
             object: profile_user.ap_id,
             activity_ap_id: nil
           }) do
      Relationships.delete_by_type_actor_object("Follow", viewer.ap_id, profile_user.ap_id)
      Relationships.delete_by_type_actor_object("Follow", profile_user.ap_id, viewer.ap_id)

      {:noreply,
       socket
       |> put_flash(:info, "Blocked #{profile_user.nickname}.")
       |> assign(
         block_relationship: relationship,
         follow_relationship: nil,
         followers_count: count_followers(profile_user),
         following_count: count_following(profile_user)
       )}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to block people.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("unblock", _params, socket) do
    with %User{} = viewer <- socket.assigns.current_user,
         %User{} = profile_user <- socket.assigns.profile_user,
         true <- viewer.id != profile_user.id do
      Relationships.delete_by_type_actor_object("Block", viewer.ap_id, profile_user.ap_id)

      {:noreply,
       socket
       |> put_flash(:info, "Unblocked #{profile_user.nickname}.")
       |> assign(block_relationship: nil)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to unblock people.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("unfollow", _params, socket) do
    with %User{} = viewer <- socket.assigns.current_user,
         %User{} = profile_user <- socket.assigns.profile_user,
         %{} = relationship <- socket.assigns.follow_relationship,
         {:ok, _undo} <-
           Pipeline.ingest(Undo.build(viewer, relationship.activity_ap_id), local: true) do
      {:noreply,
       socket
       |> put_flash(:info, "Unfollowed #{profile_user.nickname}.")
       |> assign(
         follow_relationship: nil,
         follow_request_relationship: follow_request_relationship(viewer, profile_user),
         followers_count: count_followers(profile_user)
       )}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to unfollow people.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("unfollow_request", _params, socket) do
    with %User{} = viewer <- socket.assigns.current_user,
         %User{} = profile_user <- socket.assigns.profile_user,
         %{} = relationship <- socket.assigns.follow_request_relationship,
         follow_ap_id when is_binary(follow_ap_id) and follow_ap_id != "" <-
           relationship.activity_ap_id,
         {:ok, _undo} <- Pipeline.ingest(Undo.build(viewer, follow_ap_id), local: true) do
      {:noreply,
       socket
       |> put_flash(:info, "Cancelled follow request to #{profile_user.nickname}.")
       |> assign(
         follow_relationship: follow_relationship(viewer, profile_user),
         follow_request_relationship: nil,
         followers_count: count_followers(profile_user)
       )}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to unfollow people.")}

      _ ->
        {:noreply, socket}
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
        posts =
          case socket.assigns.profile_user do
            %User{} = user ->
              viewer = socket.assigns.current_user

              Objects.list_visible_notes_by_actor(user.ap_id, viewer,
                limit: @page_size,
                max_id: cursor
              )

            _ ->
              []
          end

        socket =
          if posts == [] do
            assign(socket, posts_end?: true)
          else
            new_cursor = posts_cursor(posts)
            posts_end? = length(posts) < @page_size
            viewer = socket.assigns.current_user

            socket =
              Enum.reduce(StatusVM.decorate_many(posts, viewer), socket, fn entry, socket ->
                stream_insert(socket, :posts, entry, at: -1)
              end)

            assign(socket, posts_cursor: new_cursor, posts_end?: posts_end?)
          end

        {:noreply, socket}
    end
  end

  def handle_event("toggle_like", %{"id" => id}, socket) do
    with %User{} = user <- socket.assigns.current_user,
         {post_id, ""} <- Integer.parse(to_string(id)) do
      _ = Interactions.toggle_like(user, post_id)

      {:noreply, refresh_post(socket, post_id)}
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

      {:noreply, refresh_post(socket, post_id)}
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

      {:noreply, refresh_post(socket, post_id)}
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

      {:noreply, refresh_post(socket, post_id)}
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
      profile_user = socket.assigns.profile_user

      socket =
        socket
        |> put_flash(:info, "Post deleted.")
        |> stream_delete(:posts, %{object: %{id: post_id}})

      socket =
        case profile_user do
          %User{} ->
            assign(socket, posts_count: count_posts(profile_user, socket.assigns.current_user))

          _ ->
            socket
        end

      {:noreply, socket}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to delete posts.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not delete post.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <AppShell.app_shell
        id="profile-shell"
        nav_id="profile-nav"
        main_id="profile-main"
        active={:profile}
        current_user={@current_user}
        notifications_count={@notifications_count}
      >
        <%= if @profile_user do %>
          <section class="space-y-6">
            <.card class="overflow-hidden p-0" data_role="profile-header">
              <div
                data-role="profile-banner"
                class="relative h-32 bg-gradient-to-r from-slate-900 via-slate-800 to-rose-700 dark:from-slate-950 dark:via-slate-900 dark:to-rose-600 sm:h-36"
              >
                <img
                  :if={is_binary(@profile_user.banner_url) and @profile_user.banner_url != ""}
                  data-role="profile-banner-image"
                  src={URL.absolute(@profile_user.banner_url, @profile_user.ap_id)}
                  alt=""
                  class="absolute inset-0 h-full w-full object-cover"
                  loading="lazy"
                />
                <div class="absolute inset-0 bg-gradient-to-t from-slate-950/70 via-slate-950/10 to-transparent">
                </div>
                <div class="pointer-events-none absolute inset-0 opacity-70 mix-blend-overlay">
                  <div class="absolute -left-14 -top-10 h-40 w-40 rounded-full bg-white/10 blur-2xl">
                  </div>
                  <div class="absolute -right-12 bottom-0 h-32 w-32 rounded-full bg-white/10 blur-2xl">
                  </div>
                </div>

                <div class="absolute -bottom-10 left-6">
                  <.avatar
                    data_role="profile-avatar"
                    size="xl"
                    name={@profile_user.name || @profile_user.nickname}
                    src={URL.absolute(@profile_user.avatar_url, @profile_user.ap_id)}
                    class="ring-4 ring-white shadow-lg shadow-slate-900/10 dark:ring-slate-900 dark:shadow-slate-950/40"
                  />
                </div>
              </div>

              <div class="px-6 pb-6 pt-14 sm:pt-16">
                <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
                  <div class="min-w-0">
                    <h2
                      data-role="profile-name"
                      class="truncate font-display text-2xl text-slate-900 dark:text-slate-100"
                    >
                      {emoji_inline(
                        @profile_user.name || @profile_user.nickname,
                        @profile_user.emojis
                      )}
                    </h2>
                    <p
                      data-role="profile-handle"
                      class="mt-1 truncate text-sm text-slate-500 dark:text-slate-400"
                    >
                      {@profile_handle}
                    </p>

                    <div
                      :if={
                        @follows_you? && @current_user && @profile_user &&
                          @current_user.id != @profile_user.id
                      }
                      class="mt-3 flex flex-wrap items-center gap-2"
                      data-role="profile-badges"
                    >
                      <span
                        :if={@follows_you? && @follow_relationship}
                        data-role="profile-mutual"
                        class="inline-flex items-center rounded-full bg-emerald-100 px-3 py-1 text-xs font-semibold uppercase tracking-[0.2em] text-emerald-700 dark:bg-emerald-500/15 dark:text-emerald-200"
                      >
                        Mutual
                      </span>

                      <span
                        :if={@follows_you? && !@follow_relationship}
                        data-role="profile-follows-you"
                        class="inline-flex items-center rounded-full bg-slate-100 px-3 py-1 text-xs font-semibold uppercase tracking-[0.2em] text-slate-700 dark:bg-slate-800 dark:text-slate-100"
                      >
                        Follows you
                      </span>
                    </div>
                  </div>

                  <div class="flex flex-wrap items-center gap-2">
                    <%= if @current_user && @current_user.id != @profile_user.id do %>
                      <%= if @mute_relationship do %>
                        <button
                          type="button"
                          data-role="profile-unmute"
                          phx-click="unmute"
                          phx-disable-with="Unmuting..."
                          class="inline-flex items-center justify-center rounded-full border border-slate-200/80 bg-white/70 px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-slate-700 shadow-sm shadow-slate-200/20 transition hover:-translate-y-0.5 hover:bg-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:shadow-slate-900/40 dark:hover:bg-slate-950"
                        >
                          Unmute
                        </button>
                      <% else %>
                        <button
                          type="button"
                          data-role="profile-mute"
                          phx-click="mute"
                          phx-disable-with="Muting..."
                          class="inline-flex items-center justify-center rounded-full border border-slate-200/80 bg-white/70 px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-slate-700 shadow-sm shadow-slate-200/20 transition hover:-translate-y-0.5 hover:bg-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:shadow-slate-900/40 dark:hover:bg-slate-950"
                        >
                          Mute
                        </button>
                      <% end %>

                      <%= if @block_relationship do %>
                        <button
                          type="button"
                          data-role="profile-unblock"
                          phx-click="unblock"
                          phx-disable-with="Unblocking..."
                          class="inline-flex items-center justify-center rounded-full border border-red-200/80 bg-red-50 px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-red-700 shadow-sm shadow-red-100/30 transition hover:-translate-y-0.5 hover:bg-red-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-red-300 dark:border-red-800/70 dark:bg-red-900/30 dark:text-red-200 dark:shadow-red-900/30 dark:hover:bg-red-900/40"
                        >
                          Unblock
                        </button>
                      <% else %>
                        <button
                          type="button"
                          data-role="profile-block"
                          phx-click="block"
                          phx-disable-with="Blocking..."
                          class="inline-flex items-center justify-center rounded-full border border-red-200/80 bg-red-50 px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-red-700 shadow-sm shadow-red-100/30 transition hover:-translate-y-0.5 hover:bg-red-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-red-300 dark:border-red-800/70 dark:bg-red-900/30 dark:text-red-200 dark:shadow-red-900/30 dark:hover:bg-red-900/40"
                        >
                          Block
                        </button>
                      <% end %>

                      <%= if !@block_relationship do %>
                        <%= if @follow_relationship do %>
                          <button
                            type="button"
                            data-role="profile-unfollow"
                            phx-click="unfollow"
                            phx-disable-with="Unfollowing..."
                            class="inline-flex items-center justify-center rounded-full border border-slate-200/80 bg-white/70 px-5 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-slate-700 shadow-sm shadow-slate-200/20 transition hover:-translate-y-0.5 hover:bg-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:shadow-slate-900/40 dark:hover:bg-slate-950"
                          >
                            Unfollow
                          </button>
                        <% else %>
                          <%= if @follow_request_relationship do %>
                            <button
                              type="button"
                              data-role="profile-unfollow-request"
                              phx-click="unfollow_request"
                              phx-disable-with="Cancelling..."
                              class="inline-flex items-center justify-center rounded-full border border-amber-200/80 bg-amber-50 px-5 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-amber-800 shadow-sm shadow-amber-100/40 transition hover:-translate-y-0.5 hover:bg-amber-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-300 dark:border-amber-800/60 dark:bg-amber-900/30 dark:text-amber-100 dark:shadow-amber-900/30 dark:hover:bg-amber-900/40"
                            >
                              Requested
                            </button>
                          <% else %>
                            <button
                              type="button"
                              data-role="profile-follow"
                              phx-click="follow"
                              phx-disable-with="Following..."
                              class="inline-flex items-center justify-center rounded-full bg-slate-900 px-5 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-white shadow-lg shadow-slate-900/25 transition hover:-translate-y-0.5 hover:bg-slate-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-white"
                            >
                              Follow
                            </button>
                          <% end %>
                        <% end %>
                      <% end %>
                    <% end %>
                  </div>
                </div>

                <div
                  :if={is_binary(@profile_user.bio) and @profile_user.bio != ""}
                  data-role="profile-bio"
                  class="mt-5 max-w-prose space-y-3 text-sm text-slate-700 dark:text-slate-200 [&_a]:underline [&_a]:decoration-slate-400/60 [&_a:hover]:decoration-slate-600 dark:[&_a]:decoration-slate-500/60 dark:[&_a:hover]:decoration-slate-200"
                >
                  {@profile_bio_html}
                </div>

                <div class="mt-6 grid grid-cols-3 gap-3 sm:max-w-md">
                  <.stat value={@posts_count} label="Posts" />

                  <.link
                    navigate={ProfilePaths.followers_path(@profile_user)}
                    class="block focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400"
                  >
                    <.stat value={@followers_count} label="Followers" />
                  </.link>

                  <.link
                    navigate={ProfilePaths.following_path(@profile_user)}
                    class="block focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400"
                  >
                    <.stat value={@following_count} label="Following" />
                  </.link>
                </div>
              </div>
            </.card>

            <section class="space-y-4">
              <div class="flex flex-col gap-3 rounded-3xl border border-white/80 bg-white/80 p-5 shadow-lg shadow-slate-200/20 backdrop-blur dark:border-slate-700/60 dark:bg-slate-900/70 dark:shadow-slate-900/40 sm:flex-row sm:items-center sm:justify-between">
                <div>
                  <h3 class="font-display text-xl text-slate-900 dark:text-slate-100">
                    Posts
                  </h3>
                  <p class="mt-1 text-xs uppercase tracking-[0.3em] text-slate-500 dark:text-slate-400">
                    Latest notes
                  </p>
                </div>
              </div>

              <div id="profile-posts" phx-update="stream" class="space-y-4">
                <div
                  id="profile-posts-empty"
                  class="hidden only:block rounded-3xl border border-slate-200/80 bg-white/70 p-6 text-sm text-slate-600 shadow-sm shadow-slate-200/20 dark:border-slate-700/70 dark:bg-slate-950/50 dark:text-slate-300 dark:shadow-slate-900/30"
                >
                  No posts yet.
                </div>

                <StatusCard.status_card
                  :for={{id, entry} <- @streams.posts}
                  id={id}
                  entry={entry}
                  current_user={@current_user}
                  reply_mode={:modal}
                />
              </div>

              <div :if={!@posts_end?} class="flex justify-center py-2">
                <.button
                  data-role="profile-load-more"
                  phx-click="load_more_posts"
                  phx-disable-with="Loading..."
                  aria-label="Load more posts"
                  variant="secondary"
                >
                  <.icon name="hero-chevron-down" class="size-4" /> Load more
                </.button>
              </div>
            </section>
          </section>
        <% else %>
          <section class="space-y-4">
            <.card class="p-6">
              <p class="text-sm text-slate-600 dark:text-slate-300">
                Profile not found.
              </p>
              <div class="mt-4 flex flex-wrap items-center gap-2">
                <.button navigate={~p"/"} size="sm">Go home</.button>
              </div>
            </.card>
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

  attr :value, :integer, required: true
  attr :label, :string, required: true

  defp stat(assigns) do
    ~H"""
    <div class="rounded-2xl border border-slate-200/80 bg-white/70 px-4 py-3 text-center shadow-sm shadow-slate-200/20 dark:border-slate-700/70 dark:bg-slate-950/50 dark:shadow-slate-900/30">
      <p class="text-lg font-semibold text-slate-900 dark:text-slate-100">{@value}</p>
      <p class="text-[10px] uppercase tracking-[0.25em] text-slate-500 dark:text-slate-400">
        {@label}
      </p>
    </div>
    """
  end

  defp follow_relationship(nil, _profile_user), do: nil
  defp follow_relationship(_current_user, nil), do: nil

  defp follow_relationship(%User{} = current_user, %User{} = profile_user) do
    Relationships.get_by_type_actor_object("Follow", current_user.ap_id, profile_user.ap_id)
  end

  defp follows_you?(nil, _profile_user), do: false
  defp follows_you?(_current_user, nil), do: false

  defp follows_you?(%User{} = current_user, %User{} = profile_user) do
    if current_user.id == profile_user.id do
      false
    else
      Relationships.get_by_type_actor_object("Follow", profile_user.ap_id, current_user.ap_id) !=
        nil
    end
  end

  defp follow_request_relationship(nil, _profile_user), do: nil
  defp follow_request_relationship(_current_user, nil), do: nil

  defp follow_request_relationship(%User{} = current_user, %User{} = profile_user) do
    Relationships.get_by_type_actor_object(
      "FollowRequest",
      current_user.ap_id,
      profile_user.ap_id
    )
  end

  defp relationship_for(_type, nil, _profile_user), do: nil
  defp relationship_for(_type, _current_user, nil), do: nil

  defp relationship_for(type, %User{} = current_user, %User{} = profile_user)
       when is_binary(type) do
    Relationships.get_by_type_actor_object(type, current_user.ap_id, profile_user.ap_id)
  end

  defp count_posts(nil, _viewer), do: 0

  defp count_posts(%User{} = user, viewer),
    do: Objects.count_visible_notes_by_actor(user.ap_id, viewer)

  defp count_followers(nil), do: 0

  defp count_followers(%User{} = user),
    do: Relationships.count_by_type_object("Follow", user.ap_id)

  defp count_following(nil), do: 0

  defp count_following(%User{} = user),
    do: Relationships.count_by_type_actor("Follow", user.ap_id)

  defp posts_cursor([]), do: nil

  defp posts_cursor(posts) when is_list(posts) do
    case List.last(posts) do
      %{id: id} when is_integer(id) -> id
      _ -> nil
    end
  end

  defp post_dom_id(%{object: %{id: id}}) when is_integer(id), do: "post-#{id}"
  defp post_dom_id(_post), do: Ecto.UUID.generate()

  defp refresh_post(socket, post_id) when is_integer(post_id) do
    current_user = socket.assigns.current_user

    case Objects.get(post_id) do
      %{type: "Note"} = object ->
        if Objects.visible_to?(object, current_user) do
          stream_insert(socket, :posts, StatusVM.decorate(object, current_user))
        else
          stream_delete(socket, :posts, %{object: %{id: post_id}})
        end

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

  defp notifications_count(nil), do: 0

  defp notifications_count(%User{} = user) do
    user
    |> Notifications.list_for_user(limit: @page_size)
    |> length()
  end
end
