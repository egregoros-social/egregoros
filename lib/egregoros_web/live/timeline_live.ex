defmodule EgregorosWeb.TimelineLive do
  use EgregorosWeb, :live_view

  alias Egregoros.Badges
  alias Egregoros.Interactions
  alias Egregoros.Media
  alias Egregoros.MediaStorage
  alias Egregoros.Notifications
  alias Egregoros.Objects
  alias Egregoros.Publish
  alias Egregoros.Relationships
  alias Egregoros.Timeline
  alias Egregoros.User
  alias Egregoros.UserEvents
  alias Egregoros.Users
  alias EgregorosWeb.MentionAutocomplete
  alias EgregorosWeb.Param
  alias EgregorosWeb.ViewModels.Actor, as: ActorVM
  alias EgregorosWeb.ViewModels.Status, as: StatusVM

  @initial_page_size 10
  @page_size 20
  @poll_min_options 2
  @poll_max_options 4
  @default_poll_expiration 3600
  @impl true
  def mount(params, session, socket) do
    current_user =
      case Map.get(session, "user_id") do
        nil -> nil
        id -> Users.get(id)
      end

    timeline = timeline_from_params(params, current_user)

    timeline_topics = timeline_topics(timeline, current_user)

    if connected?(socket) do
      subscribe_topics(timeline_topics)
    end

    form = Phoenix.Component.to_form(default_post_params(), as: :post)
    reply_form = Phoenix.Component.to_form(default_post_params(), as: :reply)

    posts = list_timeline_posts(timeline, current_user, limit: @initial_page_size)
    entries = StatusVM.decorate_many(posts, current_user)

    socket =
      socket
      |> assign(
        timeline: timeline,
        home_actor_ids: home_actor_ids(current_user),
        notifications_count: notifications_count(current_user),
        compose_options_open?: false,
        compose_cw_open?: false,
        compose_poll_open?: false,
        poll_max_options: @poll_max_options,
        poll_min_options: @poll_min_options,
        reply_modal_open?: false,
        reply_to_ap_id: nil,
        reply_to_handle: nil,
        reply_form: reply_form,
        reply_media_alt: %{},
        reply_options_open?: false,
        reply_cw_open?: false,
        mention_suggestions: %{},
        error: nil,
        pending_posts: [],
        timeline_at_top?: true,
        timeline_topics: timeline_topics,
        form: form,
        media_alt: %{},
        posts_cursor: posts_cursor(posts, timeline),
        posts_end?: length(posts) < @initial_page_size,
        posts_by_feed_id: %{},
        feed_actor_ap_ids: %{},
        actor_feed_ids: %{},
        current_user: current_user
      )
      |> stream(:posts, entries, dom_id: &post_dom_id/1)
      |> track_posts(entries)
      |> allow_upload(:media,
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
    timeline = timeline_from_params(params, socket.assigns.current_user)

    socket =
      if timeline == socket.assigns.timeline do
        socket
      else
        timeline_topics = timeline_topics(timeline, socket.assigns.current_user)

        if connected?(socket) do
          unsubscribe_topics(socket.assigns.timeline_topics || [])
          subscribe_topics(timeline_topics)
        end

        posts =
          list_timeline_posts(timeline, socket.assigns.current_user, limit: @initial_page_size)

        entries = StatusVM.decorate_many(posts, socket.assigns.current_user)

        socket
        |> reset_tracked_posts()
        |> assign(
          timeline: timeline,
          pending_posts: [],
          timeline_at_top?: true,
          posts_cursor: posts_cursor(posts, timeline),
          posts_end?: length(posts) < @initial_page_size,
          timeline_topics: timeline_topics
        )
        |> stream(:posts, entries,
          reset: true,
          dom_id: &post_dom_id/1
        )
        |> track_posts(entries)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("compose_change", %{"post" => %{} = post_params}, socket) do
    post_params = normalize_compose_params(socket, post_params)
    media_alt = Map.get(post_params, "media_alt", %{})

    compose_options_open? = Param.truthy?(Map.get(post_params, "ui_options_open"))

    compose_cw_open? =
      Param.truthy?(Map.get(post_params, "ui_cw_open")) ||
        post_params |> Map.get("spoiler_text", "") |> to_string() |> String.trim() != ""

    {:noreply,
     assign(socket,
       form: Phoenix.Component.to_form(post_params, as: :post),
       media_alt: media_alt,
       compose_options_open?: compose_options_open?,
       compose_cw_open?: compose_cw_open?
     )}
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

  def handle_event("toggle_compose_poll", _params, socket) do
    post_params =
      default_post_params()
      |> Map.merge(socket.assigns.form.params || %{})

    if socket.assigns.compose_poll_open? do
      post_params = Map.delete(post_params, "poll")

      {:noreply,
       assign(socket,
         compose_poll_open?: false,
         error: nil,
         form: Phoenix.Component.to_form(post_params, as: :post)
       )}
    else
      poll_params =
        post_params
        |> Map.get("poll", %{})
        |> normalize_poll_params()

      post_params = Map.put(post_params, "poll", poll_params)

      {:noreply,
       assign(socket,
         compose_poll_open?: true,
         form: Phoenix.Component.to_form(post_params, as: :post)
       )}
    end
  end

  def handle_event("poll_add_option", _params, socket) do
    post_params =
      socket
      |> compose_params_from_form()
      |> ensure_poll_params()

    poll_params = Map.get(post_params, "poll", %{})
    options = poll_params |> Map.get("options", []) |> List.wrap()

    options =
      if length(options) < @poll_max_options do
        options ++ [""]
      else
        options
      end

    poll_params = Map.put(poll_params, "options", options)
    post_params = Map.put(post_params, "poll", poll_params)

    {:noreply, assign(socket, form: Phoenix.Component.to_form(post_params, as: :post))}
  end

  def handle_event("poll_remove_option", %{"index" => index}, socket) do
    post_params =
      socket
      |> compose_params_from_form()
      |> ensure_poll_params()

    poll_params = Map.get(post_params, "poll", %{})
    options = poll_params |> Map.get("options", []) |> List.wrap()

    options =
      if length(options) > @poll_min_options do
        case Integer.parse(to_string(index)) do
          {idx, ""} when idx >= 0 -> List.delete_at(options, idx)
          _ -> options
        end
      else
        options
      end

    poll_params = Map.put(poll_params, "options", ensure_min_poll_options(options))
    post_params = Map.put(post_params, "poll", poll_params)

    {:noreply, assign(socket, form: Phoenix.Component.to_form(post_params, as: :post))}
  end

  def handle_event("timeline_at_top", %{"at_top" => at_top}, socket) do
    at_top? = Param.truthy?(at_top)

    socket =
      socket
      |> assign(:timeline_at_top?, at_top?)
      |> maybe_flush_pending_posts(at_top?)

    {:noreply, socket}
  end

  def handle_event("copied_link", _params, socket) do
    {:noreply, put_flash(socket, :info, "Copied link to clipboard.")}
  end

  def handle_event("cancel_media", %{"ref" => ref}, socket) do
    {:noreply,
     socket
     |> cancel_upload(:media, ref)
     |> assign(:media_alt, Map.delete(socket.assigns.media_alt, ref))}
  end

  def handle_event("create_post", %{"post" => %{} = post_params}, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, assign(socket, error: "Register to post.")}

      user ->
        post_params = normalize_compose_params(socket, post_params)
        content = post_params |> Map.get("content", "") |> to_string()
        media_alt = Map.get(post_params, "media_alt", %{})
        visibility = Map.get(post_params, "visibility", "public")
        spoiler_text = Map.get(post_params, "spoiler_text")
        sensitive = Map.get(post_params, "sensitive")
        language = Map.get(post_params, "language")

        upload = socket.assigns.uploads.media

        cond do
          Enum.any?(upload.entries, &(!&1.done?)) ->
            {:noreply,
             assign(socket,
               error: "Wait for attachments to finish uploading.",
               form: Phoenix.Component.to_form(post_params, as: :post),
               media_alt: media_alt
             )}

          upload.errors != [] or Enum.any?(upload.entries, &(!&1.valid?)) ->
            {:noreply,
             assign(socket,
               error: "Remove invalid attachments before posting.",
               form: Phoenix.Component.to_form(post_params, as: :post),
               media_alt: media_alt
             )}

          true ->
            attachments =
              consume_uploaded_entries(socket, :media, fn %{path: path}, entry ->
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
                 assign(socket,
                   error: "Could not upload attachment.",
                   form: Phoenix.Component.to_form(post_params, as: :post),
                   media_alt: media_alt
                 )}

              nil ->
                publish_opts = [
                  attachments: attachments,
                  visibility: visibility,
                  spoiler_text: spoiler_text,
                  sensitive: sensitive,
                  language: language
                ]

                case publish_compose(user, content, post_params, publish_opts, socket) do
                  {:ok, _post} ->
                    {:noreply,
                     socket
                     |> put_flash(:info, "Posted.")
                     |> push_event("compose_panel_close", %{})
                     |> assign(
                       form: Phoenix.Component.to_form(default_post_params(), as: :post),
                       compose_options_open?: false,
                       compose_cw_open?: false,
                       compose_poll_open?: false,
                       error: nil,
                       media_alt: %{}
                     )}

                  {:error, :too_long} ->
                    {:noreply,
                     assign(socket,
                       error: "Post is too long.",
                       form: Phoenix.Component.to_form(post_params, as: :post),
                       media_alt: media_alt
                     )}

                  {:error, :empty} ->
                    {:noreply,
                     assign(socket,
                       error: "Post can't be empty.",
                       form: Phoenix.Component.to_form(post_params, as: :post),
                       media_alt: media_alt
                     )}

                  {:error, :invalid_poll} ->
                    {:noreply,
                     assign(socket,
                       error: "Invalid poll.",
                       form: Phoenix.Component.to_form(post_params, as: :post),
                       media_alt: media_alt
                     )}

                  {:error, :invalid} ->
                    {:noreply,
                     assign(socket,
                       error:
                         if(socket.assigns.compose_poll_open?,
                           do: "Invalid poll.",
                           else: "Could not post."
                         ),
                       form: Phoenix.Component.to_form(post_params, as: :post),
                       media_alt: media_alt
                     )}

                  {:error, message} when is_binary(message) ->
                    {:noreply,
                     assign(socket,
                       error: message,
                       form: Phoenix.Component.to_form(post_params, as: :post),
                       media_alt: media_alt
                     )}

                  {:error, _reason} ->
                    {:noreply,
                     assign(socket,
                       error: "Could not post.",
                       form: Phoenix.Component.to_form(post_params, as: :post),
                       media_alt: media_alt
                     )}
                end
            end
        end
    end
  end

  def handle_event("reply_change", %{"reply" => %{} = reply_params}, socket) do
    reply_params = Map.merge(default_post_params(), reply_params)
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
          reply_params = Map.merge(default_post_params(), reply_params)
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
                         reply_form: Phoenix.Component.to_form(default_post_params(), as: :reply),
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

  def handle_event("toggle_like", %{"id" => id} = params, socket) do
    post_id = id |> to_string() |> String.trim()

    with %User{} = user <- socket.assigns.current_user,
         true <- flake_id?(post_id) do
      _ = Interactions.toggle_like(user, post_id)

      {:noreply, refresh_post(socket, post_id, feed_id(params, post_id))}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to like posts.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_repost", %{"id" => id} = params, socket) do
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

      {:noreply, refresh_post(socket, post_id, feed_id(params, post_id))}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to repost.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_reaction", %{"id" => id, "emoji" => emoji} = params, socket) do
    post_id = id |> to_string() |> String.trim()

    with %User{} = user <- socket.assigns.current_user,
         true <- flake_id?(post_id) do
      emoji = to_string(emoji)
      _ = Interactions.toggle_reaction(user, post_id, emoji)

      {:noreply, refresh_post(socket, post_id, feed_id(params, post_id))}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to react.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_bookmark", %{"id" => id} = params, socket) do
    post_id = id |> to_string() |> String.trim()

    with %User{} = user <- socket.assigns.current_user,
         true <- flake_id?(post_id) do
      _ = Interactions.toggle_bookmark(user, post_id)

      {:noreply, refresh_post(socket, post_id, feed_id(params, post_id))}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to bookmark posts.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("vote_on_poll", %{"poll-id" => poll_id, "choices" => choices} = params, socket) do
    poll_id = poll_id |> to_string() |> String.trim()

    with %User{} = user <- socket.assigns.current_user,
         true <- flake_id?(poll_id),
         %{type: "Question"} = question <- Objects.get(poll_id),
         choices <- parse_choices(choices),
         {:ok, _updated} <- Publish.vote_on_poll(user, question, choices) do
      {:noreply,
       socket
       |> put_flash(:info, "Vote submitted!")
       |> refresh_post(poll_id, feed_id(params, poll_id))}
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

  def handle_event("vote_on_poll", %{"poll-id" => poll_id} = params, socket) do
    # Handle case where no choices were selected
    poll_id = poll_id |> to_string() |> String.trim()

    with %User{} <- socket.assigns.current_user,
         true <- flake_id?(poll_id) do
      {:noreply,
       socket
       |> put_flash(:error, "Please select at least one option.")
       |> refresh_post(poll_id, feed_id(params, poll_id))}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to vote on polls.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not submit vote.")}
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
       |> delete_post(post_id)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Register to delete posts.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not delete post.")}
    end
  end

  def handle_event("load_more", _params, socket) do
    cursor = socket.assigns.posts_cursor

    cond do
      socket.assigns.posts_end? ->
        {:noreply, socket}

      is_nil(cursor) ->
        {:noreply, assign(socket, posts_end?: true)}

      true ->
        posts =
          list_timeline_posts(socket.assigns.timeline, socket.assigns.current_user,
            limit: @page_size,
            max_id: cursor
          )

        socket =
          if posts == [] do
            assign(socket, posts_end?: true)
          else
            new_cursor = posts_cursor(posts, socket.assigns.timeline)
            posts_end? = length(posts) < @page_size
            current_user = socket.assigns.current_user

            Enum.reduce(StatusVM.decorate_many(posts, current_user), socket, fn entry, socket ->
              insert_post(socket, entry, at: -1)
            end)
            |> assign(posts_cursor: new_cursor, posts_end?: posts_end?)
          end

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:post_created, post}, socket) do
    if include_post?(
         post,
         socket.assigns.timeline,
         socket.assigns.current_user,
         socket.assigns.home_actor_ids
       ) do
      if socket.assigns.timeline_at_top? do
        cursor =
          case socket.assigns.posts_cursor do
            nil -> post.id
            existing -> min_flake_id(existing, post.id)
          end

        {:noreply,
         socket
         |> insert_post(StatusVM.decorate(post, socket.assigns.current_user), at: 0)
         |> assign(:posts_cursor, cursor)}
      else
        pending_posts =
          [post | socket.assigns.pending_posts]
          |> Enum.uniq_by(& &1.id)
          |> Enum.take(50)

        {:noreply, assign(socket, pending_posts: pending_posts)}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:post_updated, post}, socket) do
    if include_post?(
         post,
         socket.assigns.timeline,
         socket.assigns.current_user,
         socket.assigns.home_actor_ids
       ) do
      {:noreply,
       insert_post(socket, StatusVM.decorate(post, socket.assigns.current_user),
         update_only: true
       )}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:post_deleted, %{id: id}}, socket) when is_binary(id) do
    pending_posts =
      socket.assigns.pending_posts
      |> Enum.reject(&(&1.id == id))

    {:noreply,
     socket
     |> assign(pending_posts: pending_posts)
     |> delete_post(id)}
  end

  @impl true
  def handle_info({:user_updated, %{ap_id: ap_id}}, socket) do
    {:noreply, refresh_actor_posts(socket, ap_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <AppShell.app_shell
        id="timeline-shell"
        nav_id="timeline-sidebar"
        main_id="timeline-feed"
        active={:timeline}
        current_user={@current_user}
        notifications_count={@notifications_count}
      >
        <:nav_top>
          <section
            id="compose-panel"
            data-role="compose-panel"
            data-state="closed"
            phx-hook="ComposePanel"
            class={[
              "bg-[color:var(--bg-base)]",
              "fixed inset-x-4 bottom-24 z-50 max-h-[78vh] overflow-y-auto border-2 border-[color:var(--border-default)] p-4",
              "lg:static lg:inset-auto lg:bottom-auto lg:z-auto lg:max-h-none lg:overflow-visible lg:border-0 lg:p-0",
              "hidden lg:block"
            ]}
          >
            <div
              id="compose-mobile-header"
              data-role="compose-mobile-header"
              data-state="closed"
              class={[
                "mb-4 flex items-center justify-between lg:hidden",
                "hidden"
              ]}
            >
              <p class="text-xs font-bold uppercase tracking-wide text-[color:var(--text-muted)]">
                Compose
              </p>
              <button
                type="button"
                data-role="compose-close"
                phx-click={JS.dispatch("egregoros:compose-close", to: "#compose-panel")}
                class="inline-flex h-9 w-9 items-center justify-center border-2 border-[color:var(--border-default)] text-[color:var(--text-muted)] transition hover:bg-[color:var(--text-primary)] hover:text-[color:var(--bg-base)] focus-visible:outline-none focus-brutal"
                aria-label="Close composer"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>

            <%= if @current_user do %>
              <% poll_params = Map.get(@form.params || %{}, "poll", %{}) %>
              <Composer.composer_form
                id="timeline-form"
                id_prefix="compose"
                form={@form}
                upload={@uploads.media}
                media_alt={@media_alt}
                mention_suggestions={Map.get(@mention_suggestions, "compose", [])}
                error={@error}
                max_chars={5000}
                param_prefix="post"
                change_event="compose_change"
                submit_event="create_post"
                cancel_event="cancel_media"
                options_open?={@compose_options_open?}
                cw_open?={@compose_cw_open?}
                submit_label="Post"
              >
                <:after_editor>
                  <ComposerPoll.poll_fields
                    id_prefix="compose"
                    param_prefix="post"
                    poll={poll_params}
                    open?={@compose_poll_open?}
                    add_event="poll_add_option"
                    remove_event="poll_remove_option"
                    max_options={@poll_max_options}
                    min_options={@poll_min_options}
                  />
                </:after_editor>

                <:toolbar_actions>
                  <ComposerPoll.poll_toggle_button
                    id_prefix="compose"
                    open?={@compose_poll_open?}
                    toggle_event="toggle_compose_poll"
                  />
                </:toolbar_actions>
              </Composer.composer_form>
            <% else %>
              <div class="border-2 border-[color:var(--border-default)] bg-[color:var(--bg-subtle)] p-4 text-sm text-[color:var(--text-secondary)]">
                <p>Posting requires a local account.</p>
                <div class="mt-4 flex flex-wrap items-center gap-2">
                  <.button navigate={~p"/login"} size="sm">Login</.button>
                  <.button navigate={~p"/register"} variant="secondary" size="sm">Register</.button>
                </div>
              </div>
            <% end %>
          </section>
        </:nav_top>

        <section class="space-y-4">
          <div
            id="timeline-scroll-restore"
            phx-hook="ScrollRestore"
            class="sr-only"
            aria-hidden="true"
          >
          </div>

          <div
            id="timeline-top-sentinel"
            phx-hook="TimelineTopSentinel"
            class="sr-only"
            aria-hidden="true"
          >
          </div>

          <div class="flex flex-col gap-3 border-2 border-[color:var(--border-default)] bg-[color:var(--bg-base)] px-4 py-3 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <h2 class="text-xl font-bold text-[color:var(--text-primary)]">Timeline</h2>
              <p class="mt-1 font-mono text-xs uppercase text-[color:var(--text-muted)]">
                {timeline_label(@timeline)}
              </p>
              <span data-role="timeline-current" class="sr-only">{@timeline}</span>
            </div>

            <div class="flex items-center gap-2">
              <%= if @current_user do %>
                <.link
                  patch={~p"/?timeline=for_you"}
                  class={[
                    "border-2 px-4 py-2 text-xs font-bold uppercase tracking-wide transition",
                    @timeline == :for_you &&
                      "border-[color:var(--border-default)] bg-[color:var(--text-primary)] text-[color:var(--bg-base)]",
                    @timeline != :for_you &&
                      "border-[color:var(--border-default)] bg-[color:var(--bg-base)] text-[color:var(--text-secondary)] hover:bg-[color:var(--text-primary)] hover:text-[color:var(--bg-base)]"
                  ]}
                >
                  For you
                </.link>

                <.link
                  patch={~p"/?timeline=home"}
                  class={[
                    "border-2 px-4 py-2 text-xs font-bold uppercase tracking-wide transition",
                    @timeline == :home &&
                      "border-[color:var(--border-default)] bg-[color:var(--text-primary)] text-[color:var(--bg-base)]",
                    @timeline != :home &&
                      "border-[color:var(--border-default)] bg-[color:var(--bg-base)] text-[color:var(--text-secondary)] hover:bg-[color:var(--text-primary)] hover:text-[color:var(--bg-base)]"
                  ]}
                >
                  Home
                </.link>
              <% else %>
                <span class="border-2 border-[color:var(--border-muted)] bg-[color:var(--bg-subtle)] px-4 py-2 text-xs font-bold uppercase tracking-wide text-[color:var(--text-muted)]">
                  Home
                </span>
              <% end %>

              <.link
                patch={~p"/?timeline=local"}
                class={[
                  "border-2 px-4 py-2 text-xs font-bold uppercase tracking-wide transition",
                  @timeline == :local &&
                    "border-[color:var(--border-default)] bg-[color:var(--text-primary)] text-[color:var(--bg-base)]",
                  @timeline != :local &&
                    "border-[color:var(--border-default)] bg-[color:var(--bg-base)] text-[color:var(--text-secondary)] hover:bg-[color:var(--text-primary)] hover:text-[color:var(--bg-base)]"
                ]}
              >
                Local
              </.link>

              <.link
                patch={~p"/?timeline=public"}
                class={[
                  "border-2 px-4 py-2 text-xs font-bold uppercase tracking-wide transition",
                  @timeline == :public &&
                    "border-[color:var(--border-default)] bg-[color:var(--text-primary)] text-[color:var(--bg-base)]",
                  @timeline != :public &&
                    "border-[color:var(--border-default)] bg-[color:var(--bg-base)] text-[color:var(--text-secondary)] hover:bg-[color:var(--text-primary)] hover:text-[color:var(--bg-base)]"
                ]}
              >
                Public
              </.link>
            </div>
          </div>

          <% pending_count = length(@pending_posts) %>

          <button
            :if={pending_count > 0 and !@timeline_at_top?}
            type="button"
            data-role="new-posts"
            phx-click={JS.dispatch("egregoros:scroll-top")}
            class="sticky top-4 z-30 inline-flex w-full items-center justify-center gap-2 border-2 border-[color:var(--border-default)] bg-[color:var(--bg-base)] px-6 py-3 text-sm font-bold uppercase text-[color:var(--text-primary)] transition hover:bg-[color:var(--text-primary)] hover:text-[color:var(--bg-base)] focus-visible:outline-none focus-brutal"
            aria-label="Scroll to new posts"
          >
            <.icon name="hero-arrow-up" class="size-4" />
            {new_posts_label(pending_count)}
          </button>

          <div id="timeline-posts" phx-update="stream" class="space-y-4">
            <div
              id="timeline-posts-empty"
              class="hidden only:block border-2 border-[color:var(--border-default)] bg-[color:var(--bg-subtle)] p-6 text-sm text-[color:var(--text-secondary)]"
            >
              No posts yet.
            </div>

            <StatusCard.status_card
              :for={{id, entry} <- @streams.posts}
              id={id}
              entry={entry}
              current_user={@current_user}
              back_timeline={@timeline}
              reply_mode={:modal}
            />
          </div>

          <div
            :if={!@posts_end?}
            id="timeline-loading-more"
            data-role="timeline-loading-more"
            class="hidden space-y-4"
            aria-hidden="true"
          >
            <.skeleton_status_card
              :for={_ <- 1..2}
              class="border-2 border-[color:var(--border-default)]"
            />
          </div>

          <div :if={!@posts_end?} class="flex justify-center py-2">
            <.button
              data-role="load-more"
              phx-click="load_more"
              phx-disable-with="Loading..."
              aria-label="Load more posts"
              variant="secondary"
            >
              <.icon name="hero-chevron-down" class="size-4" /> Load more
            </.button>
          </div>

          <div
            :if={!@posts_end?}
            id="timeline-bottom-sentinel"
            phx-hook="TimelineBottomSentinel"
            class="h-px w-full"
            aria-hidden="true"
          >
          </div>
        </section>

        <div
          id="compose-overlay"
          data-role="compose-overlay"
          data-state="closed"
          class={[
            "fixed inset-0 z-40 bg-[color:var(--text-primary)]/50 lg:hidden",
            "hidden"
          ]}
          phx-click={JS.dispatch("egregoros:compose-close", to: "#compose-panel")}
          aria-hidden="true"
        >
        </div>

        <button
          :if={@current_user}
          type="button"
          id="compose-open-button"
          data-role="compose-open"
          data-state="visible"
          phx-click={JS.dispatch("egregoros:compose-open", to: "#compose-panel")}
          class={[
            "fixed bottom-24 right-6 z-40 inline-flex h-14 w-14 items-center justify-center border-2 border-[color:var(--border-default)] bg-[color:var(--text-primary)] text-[color:var(--bg-base)] shadow-[4px_4px_0_var(--border-default)] transition hover:shadow-none hover:translate-x-1 hover:translate-y-1 focus-visible:outline-none lg:hidden"
          ]}
          aria-label="Compose a new post"
        >
          <.icon name="hero-pencil-square" class="size-6" />
        </button>
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

  defp timeline_from_params(%{"timeline" => "public"}, _user), do: :public
  defp timeline_from_params(%{"timeline" => "local"}, _user), do: :local
  defp timeline_from_params(%{"timeline" => "for_you"}, %User{}), do: :for_you
  defp timeline_from_params(%{"timeline" => "for_you"}, _user), do: :public
  defp timeline_from_params(%{"timeline" => "home"}, %User{}), do: :home
  defp timeline_from_params(_params, %User{}), do: :home
  defp timeline_from_params(_params, _user), do: :public

  defp timeline_topics(:public, _user), do: [Timeline.public_topic()]
  defp timeline_topics(:local, _user), do: [Timeline.public_topic()]
  defp timeline_topics(:for_you, _user), do: []
  defp timeline_topics(:home, %User{} = user), do: [Timeline.user_topic(user.ap_id)]
  defp timeline_topics(_timeline, _user), do: [Timeline.public_topic()]

  defp subscribe_topics(topics) when is_list(topics) do
    Enum.each(topics, &Phoenix.PubSub.subscribe(Egregoros.PubSub, &1))
  end

  defp subscribe_topics(_topics), do: :ok

  defp unsubscribe_topics(topics) when is_list(topics) do
    Enum.each(topics, &Phoenix.PubSub.unsubscribe(Egregoros.PubSub, &1))
  end

  defp unsubscribe_topics(_topics), do: :ok

  defp track_posts(socket, entries) when is_list(entries) do
    Enum.reduce(entries, socket, fn entry, socket ->
      track_post(socket, entry)
    end)
  end

  defp track_posts(socket, _entries), do: socket

  defp insert_post(socket, entry, opts \\ [])

  defp insert_post(socket, entry, opts) when is_map(entry) and is_list(opts) do
    socket
    |> stream_insert(:posts, entry, opts)
    |> track_post(entry)
  end

  defp insert_post(socket, _entry, _opts), do: socket

  defp delete_post(socket, feed_id) do
    socket
    |> stream_delete(:posts, %{feed_id: feed_id})
    |> untrack_post(feed_id)
  end

  defp reset_tracked_posts(socket) do
    actor_feed_ids = socket.assigns.actor_feed_ids || %{}

    if connected?(socket) do
      actor_feed_ids
      |> Map.keys()
      |> Enum.each(&UserEvents.unsubscribe/1)
    end

    assign(socket,
      posts_by_feed_id: %{},
      feed_actor_ap_ids: %{},
      actor_feed_ids: %{}
    )
  end

  defp track_post(socket, %{} = entry) do
    feed_id = Map.get(entry, :feed_id) || get_in(entry, [:object, :id])

    if is_nil(feed_id) do
      socket
    else
      new_actor_ap_ids = actor_ap_ids_for_entry(entry)

      old_actor_ap_ids =
        socket.assigns.feed_actor_ap_ids
        |> Map.get(feed_id, MapSet.new())

      actor_feed_ids =
        socket.assigns.actor_feed_ids
        |> remove_feed_id_from_actors(feed_id, old_actor_ap_ids, new_actor_ap_ids)
        |> add_feed_id_to_actors(feed_id, old_actor_ap_ids, new_actor_ap_ids, connected?(socket))

      posts_by_feed_id =
        socket.assigns.posts_by_feed_id
        |> Map.put(feed_id, entry)

      feed_actor_ap_ids =
        socket.assigns.feed_actor_ap_ids
        |> Map.put(feed_id, new_actor_ap_ids)

      assign(socket,
        posts_by_feed_id: posts_by_feed_id,
        feed_actor_ap_ids: feed_actor_ap_ids,
        actor_feed_ids: actor_feed_ids
      )
    end
  end

  defp track_post(socket, _entry), do: socket

  defp untrack_post(socket, feed_id) do
    old_actor_ap_ids =
      socket.assigns.feed_actor_ap_ids
      |> Map.get(feed_id, MapSet.new())

    actor_feed_ids =
      socket.assigns.actor_feed_ids
      |> remove_feed_id_from_actors(feed_id, old_actor_ap_ids, MapSet.new())

    assign(socket,
      posts_by_feed_id: Map.delete(socket.assigns.posts_by_feed_id, feed_id),
      feed_actor_ap_ids: Map.delete(socket.assigns.feed_actor_ap_ids, feed_id),
      actor_feed_ids: actor_feed_ids
    )
  end

  defp actor_ap_ids_for_entry(%{} = entry) do
    [
      get_in(entry, [:actor, :ap_id]),
      get_in(entry, [:reposted_by, :ap_id])
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> MapSet.new()
  end

  defp actor_ap_ids_for_entry(_entry), do: MapSet.new()

  defp remove_feed_id_from_actors(
         actor_feed_ids,
         feed_id,
         old_actor_ap_ids,
         new_actor_ap_ids
       )
       when is_map(actor_feed_ids) do
    removed_actor_ap_ids = MapSet.difference(old_actor_ap_ids, new_actor_ap_ids)

    Enum.reduce(removed_actor_ap_ids, actor_feed_ids, fn actor_ap_id, actor_feed_ids ->
      feed_ids =
        actor_feed_ids
        |> Map.get(actor_ap_id, MapSet.new())
        |> MapSet.delete(feed_id)

      if MapSet.size(feed_ids) == 0 do
        _ = UserEvents.unsubscribe(actor_ap_id)
        Map.delete(actor_feed_ids, actor_ap_id)
      else
        Map.put(actor_feed_ids, actor_ap_id, feed_ids)
      end
    end)
  end

  defp remove_feed_id_from_actors(actor_feed_ids, _feed_id, _old_actor_ap_ids, _new_actor_ap_ids),
    do: actor_feed_ids

  defp add_feed_id_to_actors(
         actor_feed_ids,
         feed_id,
         old_actor_ap_ids,
         new_actor_ap_ids,
         subscribe?
       )
       when is_map(actor_feed_ids) and is_boolean(subscribe?) do
    added_actor_ap_ids = MapSet.difference(new_actor_ap_ids, old_actor_ap_ids)

    Enum.reduce(added_actor_ap_ids, actor_feed_ids, fn actor_ap_id, actor_feed_ids ->
      feed_ids =
        actor_feed_ids
        |> Map.get(actor_ap_id, MapSet.new())
        |> MapSet.put(feed_id)

      if subscribe? do
        _ = UserEvents.subscribe(actor_ap_id)
      end

      Map.put(actor_feed_ids, actor_ap_id, feed_ids)
    end)
  end

  defp add_feed_id_to_actors(actor_feed_ids, _feed_id, _old_actor_ap_ids, _new_actor_ap_ids, _),
    do: actor_feed_ids

  defp refresh_actor_posts(socket, ap_id) when is_binary(ap_id) do
    ap_id = String.trim(ap_id)

    if ap_id == "" do
      socket
    else
      feed_ids = Map.get(socket.assigns.actor_feed_ids, ap_id, MapSet.new())

      if MapSet.size(feed_ids) == 0 do
        socket
      else
        updated_card = ActorVM.card(ap_id)

        Enum.reduce(feed_ids, socket, fn feed_id, socket ->
          case Map.get(socket.assigns.posts_by_feed_id, feed_id) do
            %{} = entry ->
              entry = replace_actor_card(entry, ap_id, updated_card)

              insert_post(socket, entry, update_only: true)

            _ ->
              socket
          end
        end)
      end
    end
  end

  defp refresh_actor_posts(socket, _ap_id), do: socket

  defp replace_actor_card(%{} = entry, ap_id, updated_card)
       when is_binary(ap_id) and is_map(updated_card) do
    entry =
      if get_in(entry, [:actor, :ap_id]) == ap_id do
        Map.put(entry, :actor, updated_card)
      else
        entry
      end

    if get_in(entry, [:reposted_by, :ap_id]) == ap_id do
      Map.put(entry, :reposted_by, updated_card)
    else
      entry
    end
  end

  defp replace_actor_card(entry, _ap_id, _updated_card), do: entry

  defp list_timeline_posts(:home, %User{} = user, opts) when is_list(opts) do
    Objects.list_home_statuses(user.ap_id, opts)
  end

  defp list_timeline_posts(:for_you, %User{} = user, opts) when is_list(opts) do
    Objects.list_for_you_statuses(user.ap_id, opts)
  end

  defp list_timeline_posts(:local, _user, opts) when is_list(opts) do
    Objects.list_public_statuses(Keyword.put(opts, :local, true))
  end

  defp list_timeline_posts(_timeline, _user, opts) when is_list(opts) do
    Objects.list_public_statuses(opts)
  end

  defp posts_cursor([], _timeline), do: nil

  defp posts_cursor(posts, :for_you) when is_list(posts) do
    post = List.last(posts)

    cond do
      match?(%{internal: %{"for_you_like_id" => like_id}} when is_binary(like_id), post) ->
        %{"for_you_like_id" => like_id} = post.internal
        like_id

      match?(%{internal: %{for_you_like_id: like_id}} when is_binary(like_id), post) ->
        %{for_you_like_id: like_id} = post.internal
        like_id

      true ->
        nil
    end
  end

  defp posts_cursor(posts, _timeline) when is_list(posts) do
    case List.last(posts) do
      %{id: id} when is_binary(id) -> id
      _ -> nil
    end
  end

  defp post_dom_id(%{feed_id: id}) when is_binary(id), do: "post-#{id}"
  defp post_dom_id(%{object: %{id: id}}) when is_binary(id), do: "post-#{id}"
  defp post_dom_id(_post), do: Ecto.UUID.generate()

  @timeline_types ["Note", "Announce", "Question"]

  defp include_post?(%{type: type} = post, :home, %User{} = user, home_actor_ids)
       when type in @timeline_types and is_list(home_actor_ids) do
    cond do
      not Objects.visible_to?(post, user) ->
        false

      post.actor == user.ap_id ->
        true

      is_binary(post.actor) and post.actor in home_actor_ids ->
        true

      addressed_to_user?(post, user.ap_id) ->
        true

      true ->
        false
    end
  end

  defp include_post?(%{type: type} = post, :public, _user, _home_actor_ids)
       when type in @timeline_types do
    Objects.publicly_listed?(post)
  end

  defp include_post?(%{type: type, local: true} = post, :local, _user, _home_actor_ids)
       when type in @timeline_types do
    Objects.publicly_listed?(post)
  end

  defp include_post?(%{type: type} = _post, :local, _user, _home_actor_ids)
       when type in @timeline_types,
       do: false

  defp include_post?(_post, :for_you, _user, _home_actor_ids), do: false

  defp include_post?(_post, _timeline, _user, _home_actor_ids), do: false

  @recipient_fields ~w(to cc bto bcc audience)

  defp addressed_to_user?(%{data: %{} = data}, user_ap_id) when is_binary(user_ap_id) do
    user_ap_id = String.trim(user_ap_id)

    if user_ap_id == "" do
      false
    else
      Enum.any?(@recipient_fields, fn field ->
        data
        |> Map.get(field)
        |> List.wrap()
        |> Enum.any?(fn
          %{"id" => id} when is_binary(id) -> String.trim(id) == user_ap_id
          %{id: id} when is_binary(id) -> String.trim(id) == user_ap_id
          id when is_binary(id) -> String.trim(id) == user_ap_id
          _ -> false
        end)
      end)
    end
  end

  defp addressed_to_user?(_post, _user_ap_id), do: false

  defp home_actor_ids(nil), do: []

  defp home_actor_ids(%User{} = user) do
    followed_actor_ids =
      user.ap_id
      |> Relationships.list_follows_by_actor()
      |> Enum.map(& &1.object)
      |> Enum.filter(&is_binary/1)

    Enum.uniq([user.ap_id | followed_actor_ids])
  end

  defp normalize_compose_params(socket, post_params) do
    post_params = default_post_params() |> Map.merge(post_params)

    if socket.assigns.compose_poll_open? do
      poll_params =
        post_params
        |> Map.get("poll")
        |> Kernel.||(Map.get(socket.assigns.form.params || %{}, "poll"))
        |> Kernel.||(default_poll_params())
        |> normalize_poll_params()

      Map.put(post_params, "poll", poll_params)
    else
      Map.delete(post_params, "poll")
    end
  end

  defp compose_params_from_form(socket) do
    default_post_params()
    |> Map.merge(socket.assigns.form.params || %{})
  end

  defp ensure_poll_params(post_params) do
    poll_params =
      post_params
      |> Map.get("poll", %{})
      |> normalize_poll_params()

    Map.put(post_params, "poll", poll_params)
  end

  defp publish_compose(%User{} = user, content, post_params, opts, socket) do
    poll_params = Map.get(post_params, "poll")

    if socket.assigns.compose_poll_open? and is_map(poll_params) do
      Publish.post_poll(user, content, poll_params, opts)
    else
      Publish.post_note(user, content, opts)
    end
  end

  defp default_post_params do
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

  defp default_poll_params do
    %{
      "options" => List.duplicate("", @poll_min_options),
      "multiple" => "false",
      "expires_in" => @default_poll_expiration
    }
  end

  defp normalize_poll_params(poll_params) when is_map(poll_params) do
    options =
      poll_params
      |> Map.get("options")
      |> Kernel.||(Map.get(poll_params, :options))
      |> List.wrap()
      |> Enum.map(&to_string/1)
      |> ensure_min_poll_options()

    multiple? = Param.truthy?(Map.get(poll_params, "multiple") || Map.get(poll_params, :multiple))

    expires_in =
      poll_params
      |> Map.get("expires_in")
      |> Kernel.||(Map.get(poll_params, :expires_in))
      |> normalize_poll_expires_in()

    %{
      "options" => options,
      "multiple" => if(multiple?, do: "true", else: "false"),
      "expires_in" => expires_in
    }
  end

  defp normalize_poll_params(_poll_params), do: default_poll_params()

  defp ensure_min_poll_options(options) when is_list(options) do
    if length(options) < @poll_min_options do
      options ++ List.duplicate("", @poll_min_options - length(options))
    else
      options
    end
  end

  defp ensure_min_poll_options(_options), do: List.duplicate("", @poll_min_options)

  defp normalize_poll_expires_in(value) when is_integer(value), do: value

  defp normalize_poll_expires_in(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> @default_poll_expiration
    end
  end

  defp normalize_poll_expires_in(_value), do: @default_poll_expiration

  defp notifications_count(nil), do: 0

  defp notifications_count(%User{} = user) do
    user
    |> Notifications.list_for_user(limit: 20, include_offers?: true)
    |> length()
  end

  defp maybe_flush_pending_posts(socket, true) do
    pending_posts = socket.assigns.pending_posts

    if pending_posts == [] do
      assign(socket, pending_posts: [])
    else
      current_user = socket.assigns.current_user

      {socket, cursor} =
        Enum.reduce(Enum.reverse(pending_posts), {socket, socket.assigns.posts_cursor}, fn post,
                                                                                           {socket,
                                                                                            cursor} ->
          socket = insert_post(socket, StatusVM.decorate(post, current_user), at: 0)

          cursor =
            case cursor do
              nil -> post.id
              existing -> min_flake_id(existing, post.id)
            end

          {socket, cursor}
        end)

      socket
      |> assign(pending_posts: [], posts_cursor: cursor)
    end
  end

  defp maybe_flush_pending_posts(socket, _at_top?), do: socket

  defp new_posts_label(count) when is_integer(count) and count == 1, do: "1 new post"
  defp new_posts_label(count) when is_integer(count) and count > 1, do: "#{count} new posts"
  defp new_posts_label(_count), do: "New posts"

  defp timeline_label(:home), do: "Home"
  defp timeline_label(:for_you), do: "For you"
  defp timeline_label(:public), do: "Public"
  defp timeline_label(:local), do: "Local"
  defp timeline_label(_timeline), do: "Public"

  defp refresh_post(socket, post_id, feed_id)
       when is_binary(post_id) and is_binary(feed_id) do
    current_user = socket.assigns.current_user

    case Objects.get(post_id) do
      %{type: type} = object when type in ["Note", "Question", "VerifiableCredential"] ->
        if Objects.visible_to?(object, current_user) do
          if feed_id == post_id do
            insert_post(socket, StatusVM.decorate(object, current_user))
          else
            socket
            |> insert_post(StatusVM.decorate(object, current_user), update_only: true)
            |> refresh_announce_post(feed_id, current_user)
          end
        else
          delete_post(socket, feed_id)
        end

      _ ->
        socket
    end
  end

  defp refresh_announce_post(socket, feed_id, current_user)
       when is_binary(feed_id) do
    case Objects.get(feed_id) do
      nil ->
        delete_post(socket, feed_id)

      %{type: "Announce"} = announce ->
        case StatusVM.decorate(announce, current_user) do
          nil -> delete_post(socket, feed_id)
          entry -> insert_post(socket, entry)
        end

      _ ->
        socket
    end
  end

  defp feed_id(%{} = params, fallback) when is_binary(fallback) do
    case Map.get(params, "feed_id") do
      nil ->
        fallback

      value ->
        id = value |> to_string() |> String.trim()
        if flake_id?(id), do: id, else: fallback
    end
  end

  defp feed_id(_params, fallback), do: fallback

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

  defp min_flake_id(left, right) when is_binary(left) and is_binary(right) do
    left = String.trim(left)
    right = String.trim(right)

    with true <- flake_id?(left),
         true <- flake_id?(right) do
      <<_::128>> = left_bin = FlakeId.from_string(left)
      <<_::128>> = right_bin = FlakeId.from_string(right)

      if left_bin <= right_bin, do: left, else: right
    else
      _ -> left
    end
  end

  defp min_flake_id(nil, right) when is_binary(right), do: right
  defp min_flake_id(left, _right), do: left
end
