defmodule EgregorosWeb.BadgesLive do
  use EgregorosWeb, :live_view

  alias Egregoros.ActivityPub.TypeNormalizer
  alias Egregoros.Activities.Helpers, as: ActivityHelpers
  alias Egregoros.Badges
  alias Egregoros.Interactions
  alias Egregoros.Notifications
  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.User
  alias Egregoros.Users
  alias EgregorosWeb.ProfilePaths
  alias EgregorosWeb.URL
  alias EgregorosWeb.ViewModels.Actor, as: ActorVM

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

    {:ok,
     socket
     |> assign(
       current_user: current_user,
       profile_user: profile_user,
       profile_handle: profile_handle,
       notifications_count: notifications_count(current_user),
       badge: nil,
       badges_end?: true,
       badges_cursor: nil,
       page_title: "Badges"
     )
     |> stream(:badges, [], dom_id: &badge_dom_id/1)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      case socket.assigns.live_action do
        :show -> apply_show(socket, params)
        _ -> apply_index(socket)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_repost", %{"id" => id}, socket) do
    post_id = id |> to_string() |> String.trim()

    case socket.assigns.current_user do
      %User{} = user ->
        case Interactions.toggle_repost(user, post_id) do
          {:ok, _} ->
            socket =
              case Badges.badge_share_flash_message(user, post_id) do
                message when is_binary(message) and message != "" ->
                  put_flash(socket, :info, message)

                _ ->
                  socket
              end

            {:noreply, socket}

          _ ->
            {:noreply, socket}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Register to share badges.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <AppShell.app_shell
        id="badges-shell"
        nav_id="badges-nav"
        main_id="badges-main"
        active={:badges}
        current_user={@current_user}
        notifications_count={@notifications_count}
      >
        <%= if @profile_user do %>
          <section class="space-y-6">
            <.card class="p-6">
              <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
                <div>
                  <p class="text-xs font-bold uppercase tracking-wide text-[color:var(--text-muted)]">
                    Badges
                  </p>
                  <h2 class="mt-2 text-2xl font-bold text-[color:var(--text-primary)]">
                    {@profile_user.name || @profile_user.nickname}
                  </h2>
                  <p class="mt-1 font-mono text-sm text-[color:var(--text-muted)]">
                    {@profile_handle}
                  </p>
                </div>
                <.link
                  :if={ProfilePaths.profile_path(@profile_user)}
                  navigate={ProfilePaths.profile_path(@profile_user)}
                  class="text-xs font-bold uppercase tracking-wide text-[color:var(--text-secondary)] hover:text-[color:var(--text-primary)] hover:underline underline-offset-4"
                >
                  Back to profile
                </.link>
              </div>
            </.card>

            <%= if @live_action == :show do %>
              <%= if @badge do %>
                <.badge_detail
                  badge={@badge}
                  profile_user={@profile_user}
                  current_user={@current_user}
                />
              <% else %>
                <.card class="p-6">
                  <p class="text-sm text-[color:var(--text-secondary)]">
                    Badge not found.
                  </p>
                  <div class="mt-4 flex flex-wrap items-center gap-2">
                    <.button
                      :if={badges_path(@profile_user)}
                      navigate={badges_path(@profile_user)}
                      size="sm"
                      variant="secondary"
                    >
                      View all badges
                    </.button>
                  </div>
                </.card>
              <% end %>
            <% else %>
              <div
                id="badges-list"
                data-role="badges-list"
                phx-update="stream"
                class="space-y-4"
              >
                <div
                  id="badges-empty"
                  class="hidden only:block border-2 border-[color:var(--border-default)] bg-[color:var(--bg-subtle)] p-6 text-sm text-[color:var(--text-secondary)]"
                >
                  No badges yet.
                </div>

                <.badge_card
                  :for={{id, badge} <- @streams.badges}
                  id={id}
                  badge={badge}
                  current_user={@current_user}
                />
              </div>
            <% end %>
          </section>
        <% else %>
          <section class="space-y-4">
            <.card class="p-6">
              <p class="text-sm text-[color:var(--text-secondary)]">
                Profile not found.
              </p>
              <div class="mt-4 flex flex-wrap items-center gap-2">
                <.button navigate={~p"/"} size="sm">Go home</.button>
              </div>
            </.card>
          </section>
        <% end %>
      </AppShell.app_shell>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyToClipboard">
        const copyText = (text) => {
          if (!text) return;
          if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text);
            return;
          }
          const textarea = document.createElement("textarea");
          textarea.value = text;
          textarea.setAttribute("readonly", "");
          textarea.style.position = "absolute";
          textarea.style.left = "-9999px";
          document.body.appendChild(textarea);
          textarea.select();
          document.execCommand("copy");
          document.body.removeChild(textarea);
        };

        export default {
          mounted() {
            this.handleClick = () => {
              const text = this.el.dataset.copyText || "";
              if (text) {
                copyText(text);
              }
            };
            this.el.addEventListener("click", this.handleClick);
          },
          destroyed() {
            if (this.handleClick) {
              this.el.removeEventListener("click", this.handleClick);
            }
          }
        };
      </script>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :badge, :map, required: true
  attr :current_user, :any, default: nil

  defp badge_card(assigns) do
    ~H"""
    <article
      id={@id}
      data-role="badge-card"
      class="group border-2 border-[color:var(--border-default)] bg-[color:var(--bg-base)] p-5 transition hover:-translate-y-0.5 hover:shadow-[4px_4px_0_var(--border-default)]"
    >
      <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div class="flex items-start gap-4">
          <div class="flex h-16 w-16 items-center justify-center overflow-hidden border-2 border-[color:var(--border-default)] bg-[color:var(--bg-subtle)]">
            <%= if is_binary(@badge.image_url) and @badge.image_url != "" do %>
              <img
                data-role="badge-image"
                src={@badge.image_url}
                alt={@badge.title || "Badge"}
                class="h-full w-full object-contain"
                loading="lazy"
              />
            <% else %>
              <.icon name="hero-trophy" class="size-7 text-[color:var(--text-muted)]" />
            <% end %>
          </div>

          <div class="min-w-0">
            <p data-role="badge-title" class="text-lg font-bold text-[color:var(--text-primary)]">
              {@badge.title || "Badge"}
            </p>
            <p
              :if={@badge.description}
              data-role="badge-description"
              class="mt-1 text-sm text-[color:var(--text-secondary)]"
            >
              {@badge.description}
            </p>

            <div class="mt-3 flex flex-wrap items-center gap-2 text-xs">
              <span
                data-role="badge-validity"
                class={[
                  "inline-flex items-center border px-2 py-1 font-bold uppercase tracking-wide",
                  validity_classes(@badge.validity)
                ]}
              >
                {@badge.validity}
              </span>

              <span :if={@badge.valid_range} class="font-mono text-[color:var(--text-muted)]">
                {@badge.valid_range}
              </span>
            </div>
          </div>
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <.button
            :if={@badge.badge_path}
            navigate={@badge.badge_path}
            size="sm"
            variant="secondary"
            data-role="badge-view"
          >
            View badge
          </.button>
          <button
            :if={is_binary(@badge.credential_ap_id) and @badge.credential_ap_id != ""}
            id={"#{@id}-copy-url"}
            type="button"
            data-role="badge-copy-url"
            data-copy-text={@badge.credential_ap_id}
            phx-hook=".CopyToClipboard"
            class="inline-flex cursor-pointer items-center gap-2 border-2 border-[color:var(--border-default)] bg-[color:var(--bg-base)] px-3 py-1.5 text-xs font-bold uppercase tracking-wide text-[color:var(--text-primary)] transition hover:bg-[color:var(--bg-muted)]"
            title="Copy badge URL"
            aria-label="Copy badge URL"
          >
            📋 Copy URL
          </button>
          <button
            :if={@current_user && is_binary(@badge.credential_id)}
            type="button"
            data-role="badge-share"
            phx-click={JS.push("toggle_repost", value: %{"id" => @badge.credential_id})}
            class="inline-flex cursor-pointer items-center gap-2 border-2 border-[color:var(--border-default)] bg-[color:var(--bg-base)] px-3 py-1.5 text-xs font-bold uppercase tracking-wide text-[color:var(--text-primary)] transition hover:bg-[color:var(--bg-muted)]"
          >
            <.icon name="hero-arrow-path" class="size-4" /> Share badge
          </button>
        </div>
      </div>
    </article>
    """
  end

  attr :badge, :map, required: true
  attr :profile_user, :any, required: true
  attr :current_user, :any, default: nil

  defp badge_detail(assigns) do
    ~H"""
    <.card class="p-6" data_role="badge-detail">
      <div class="flex flex-col gap-6 lg:flex-row lg:items-start">
        <div class="flex h-40 w-40 items-center justify-center overflow-hidden border-2 border-[color:var(--border-default)] bg-[color:var(--bg-subtle)]">
          <%= if is_binary(@badge.image_url) and @badge.image_url != "" do %>
            <img
              data-role="badge-image"
              src={@badge.image_url}
              alt={@badge.title || "Badge"}
              class="h-full w-full object-contain"
              loading="lazy"
            />
          <% else %>
            <.icon name="hero-trophy" class="size-12 text-[color:var(--text-muted)]" />
          <% end %>
        </div>

        <div class="min-w-0 flex-1">
          <p class="text-xs font-bold uppercase tracking-wide text-[color:var(--text-muted)]">
            Badge
          </p>
          <h3 data-role="badge-title" class="mt-2 text-2xl font-bold text-[color:var(--text-primary)]">
            {@badge.title || "Badge"}
          </h3>
          <p
            :if={@badge.description}
            data-role="badge-description"
            class="mt-2 text-sm text-[color:var(--text-secondary)]"
          >
            {@badge.description}
          </p>

          <div class="mt-4 flex flex-wrap items-center gap-3">
            <span
              data-role="badge-validity"
              class={[
                "inline-flex items-center border px-3 py-1 text-xs font-bold uppercase tracking-wide",
                validity_classes(@badge.validity)
              ]}
            >
              {@badge.validity}
            </span>
            <span :if={@badge.valid_range} class="font-mono text-xs text-[color:var(--text-muted)]">
              {@badge.valid_range}
            </span>
          </div>

          <div class="mt-6 flex flex-wrap items-center gap-2">
            <.button
              :if={badges_path(@profile_user)}
              navigate={badges_path(@profile_user)}
              size="sm"
              variant="secondary"
            >
              All badges
            </.button>
            <button
              :if={is_binary(@badge.credential_ap_id) and @badge.credential_ap_id != ""}
              id={"badge-copy-url-#{@badge.accept.id}"}
              type="button"
              data-role="badge-copy-url"
              data-copy-text={@badge.credential_ap_id}
              phx-hook=".CopyToClipboard"
              class="inline-flex cursor-pointer items-center gap-2 border-2 border-[color:var(--border-default)] bg-[color:var(--bg-base)] px-3 py-1.5 text-xs font-bold uppercase tracking-wide text-[color:var(--text-primary)] transition hover:bg-[color:var(--bg-muted)]"
              title="Copy badge URL"
              aria-label="Copy badge URL"
            >
              📋 Copy URL
            </button>
            <button
              :if={@current_user && is_binary(@badge.credential_id)}
              type="button"
              data-role="badge-share"
              phx-click={JS.push("toggle_repost", value: %{"id" => @badge.credential_id})}
              class="inline-flex cursor-pointer items-center gap-2 border-2 border-[color:var(--border-default)] bg-[color:var(--bg-base)] px-3 py-1.5 text-xs font-bold uppercase tracking-wide text-[color:var(--text-primary)] transition hover:bg-[color:var(--bg-muted)]"
            >
              <.icon name="hero-arrow-path" class="size-4" /> Share badge
            </button>
            <.button
              :if={ProfilePaths.profile_path(@profile_user)}
              navigate={ProfilePaths.profile_path(@profile_user)}
              size="sm"
              variant="ghost"
            >
              Back to profile
            </.button>
          </div>
        </div>
      </div>
    </.card>
    """
  end

  defp apply_index(socket) do
    case socket.assigns.profile_user do
      %User{} = user ->
        accepts = list_accepts(user, limit: @page_size)
        badges = decorate_badges(accepts, user)

        socket
        |> assign(
          badge: nil,
          badges_cursor: badges_cursor(accepts),
          badges_end?: length(accepts) < @page_size,
          page_title: "#{user.nickname} - Badges"
        )
        |> stream(:badges, badges, reset: true)

      _ ->
        socket
        |> assign(
          badge: nil,
          badges_cursor: nil,
          badges_end?: true,
          page_title: "Badges"
        )
        |> stream(:badges, [], reset: true)
    end
  end

  defp apply_show(socket, %{"id" => badge_id}) do
    badge =
      case socket.assigns.profile_user do
        %User{} = user -> fetch_badge(user, badge_id)
        _ -> nil
      end

    title =
      case badge do
        %{title: title} when is_binary(title) and title != "" -> "#{title} - Badge"
        _ -> "Badge"
      end

    assign(socket, badge: badge, page_title: title)
  end

  defp apply_show(socket, _params) do
    assign(socket, badge: nil, page_title: "Badge")
  end

  defp list_accepts(%User{} = user, opts) when is_list(opts) do
    Objects.list_by_type_actor("Accept", user.ap_id, opts)
  end

  defp list_accepts(_user, _opts), do: []

  defp decorate_badges(accepts, %User{} = user) when is_list(accepts) do
    accepts
    |> Enum.map(&badge_entry(&1, user))
    |> Enum.filter(& &1)
  end

  defp decorate_badges(_accepts, _user), do: []

  defp badge_entry(%Object{} = accept, %User{} = user) do
    offer_data = offer_data_from_accept(accept)
    offer_actor = offer_actor_from_offer(offer_data, accept)
    credential = credential_from_offer(offer_data, accept)

    if TypeNormalizer.primary_type(credential) == "VerifiableCredential" do
      achievement =
        credential
        |> credential_subject()
        |> credential_achievement()

      title = achievement_field(achievement, "name")
      description = achievement_field(achievement, "description")
      image = achievement_image(achievement)

      valid_from = ActivityHelpers.parse_datetime(Map.get(credential, "validFrom"))
      valid_until = ActivityHelpers.parse_datetime(Map.get(credential, "validUntil"))
      credential_ap_id = credential_ap_id(credential)
      credential_id = credential_object_id(credential_ap_id)

      %{
        accept: accept,
        title: title,
        description: description,
        image_url: absolute_image_url(image, offer_actor),
        valid_from: valid_from,
        valid_until: valid_until,
        valid_range: validity_range(valid_from, valid_until),
        validity: validity_label(valid_from, valid_until),
        badge_path: badge_path(user, accept),
        credential_id: credential_id,
        credential_ap_id: credential_ap_id
      }
    else
      nil
    end
  end

  defp badge_entry(_accept, _user), do: nil

  defp badge_entry_from_credential(%Object{data: %{} = data} = credential, %User{} = user) do
    recipient_ap_id = credential_subject_id(data)

    if TypeNormalizer.primary_type(data) == "VerifiableCredential" and
         recipient_ap_id == user.ap_id do
      achievement =
        data
        |> credential_subject()
        |> credential_achievement()

      title = achievement_field(achievement, "name")
      description = achievement_field(achievement, "description")
      image = achievement_image(achievement)

      valid_from = ActivityHelpers.parse_datetime(Map.get(data, "validFrom"))
      valid_until = ActivityHelpers.parse_datetime(Map.get(data, "validUntil"))

      %{
        accept: credential,
        title: title,
        description: description,
        image_url: absolute_image_url(image, credential.actor),
        valid_from: valid_from,
        valid_until: valid_until,
        valid_range: validity_range(valid_from, valid_until),
        validity: validity_label(valid_from, valid_until),
        badge_path: badge_path(user, credential),
        credential_id: credential.id,
        credential_ap_id: credential.ap_id
      }
    else
      nil
    end
  end

  defp badge_entry_from_credential(_credential, _user), do: nil

  defp offer_data_from_accept(%Object{} = accept) do
    cond do
      match?(%{"object" => %{}}, accept.data) ->
        Map.get(accept.data, "object")

      true ->
        offer_object_from_accept(accept)
        |> case do
          %Object{data: %{} = data} -> data
          _ -> nil
        end
    end
  end

  defp offer_data_from_accept(_accept), do: nil

  defp offer_object_from_accept(%Object{object: offer_ap_id}) when is_binary(offer_ap_id) do
    Objects.get_by_ap_id(offer_ap_id)
  end

  defp offer_object_from_accept(_accept), do: nil

  defp offer_actor_from_offer(%{"actor" => actor}, _accept) when is_binary(actor), do: actor

  defp offer_actor_from_offer(_offer_data, %Object{} = accept) do
    case offer_object_from_accept(accept) do
      %Object{actor: actor} when is_binary(actor) -> actor
      _ -> nil
    end
  end

  defp offer_actor_from_offer(_offer_data, _accept), do: nil

  defp credential_from_offer(%{"object" => %{} = embedded}, _accept), do: embedded

  defp credential_from_offer(%{"object" => credential_ap_id}, _accept)
       when is_binary(credential_ap_id) do
    credential_from_ap_id(credential_ap_id)
  end

  defp credential_from_offer(_offer_data, %Object{} = accept) do
    offer_object = offer_object_from_accept(accept)

    case offer_object do
      %Object{data: %{"object" => %{} = embedded}} ->
        embedded

      %Object{data: %{"object" => credential_ap_id}} when is_binary(credential_ap_id) ->
        credential_from_ap_id(credential_ap_id)

      %Object{object: credential_ap_id} when is_binary(credential_ap_id) ->
        credential_from_ap_id(credential_ap_id)

      _ ->
        nil
    end
  end

  defp credential_from_offer(_offer_data, _accept), do: nil

  defp credential_from_ap_id(credential_ap_id) when is_binary(credential_ap_id) do
    case Objects.get_by_ap_id(credential_ap_id) do
      %Object{data: %{} = data} -> data
      _ -> nil
    end
  end

  defp credential_from_ap_id(_credential_ap_id), do: nil

  defp credential_ap_id(%{} = credential) do
    Map.get(credential, "id") || Map.get(credential, :id)
  end

  defp credential_ap_id(_credential), do: nil

  defp credential_object_id(credential_ap_id) when is_binary(credential_ap_id) do
    case Objects.get_by_ap_id(credential_ap_id) do
      %Object{id: id} -> id
      _ -> nil
    end
  end

  defp credential_object_id(_credential_ap_id), do: nil

  defp credential_subject(%{} = credential) do
    credential
    |> Map.get("credentialSubject")
    |> List.wrap()
    |> Enum.find(&is_map/1)
  end

  defp credential_subject(_credential), do: nil

  defp credential_subject_id(%{} = credential) do
    case credential_subject(credential) do
      %{"id" => id} when is_binary(id) -> id
      %{id: id} when is_binary(id) -> id
      _ -> nil
    end
  end

  defp credential_subject_id(_credential), do: nil

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

  defp absolute_image_url(nil, _base), do: nil

  defp absolute_image_url(url, base) when is_binary(url) do
    if is_binary(base) do
      URL.absolute(url, base)
    else
      URL.absolute(url)
    end
  end

  defp absolute_image_url(%{"id" => id}, base) when is_binary(id),
    do: absolute_image_url(id, base)

  defp absolute_image_url(%{"url" => url}, base) when is_binary(url),
    do: absolute_image_url(url, base)

  defp absolute_image_url(%{id: id}, base) when is_binary(id), do: absolute_image_url(id, base)

  defp absolute_image_url(%{url: url}, base) when is_binary(url),
    do: absolute_image_url(url, base)

  defp absolute_image_url(_image, _base), do: nil

  defp validity_label(valid_from, valid_until) do
    now = DateTime.utc_now()

    cond do
      match?(%DateTime{}, valid_from) and DateTime.compare(now, valid_from) == :lt ->
        "Not yet valid"

      match?(%DateTime{}, valid_until) and DateTime.compare(now, valid_until) == :gt ->
        "Expired"

      true ->
        "Valid"
    end
  end

  defp validity_range(valid_from, valid_until) do
    cond do
      match?(%DateTime{}, valid_from) and match?(%DateTime{}, valid_until) ->
        "#{format_date(valid_from)} - #{format_date(valid_until)}"

      match?(%DateTime{}, valid_until) ->
        "Valid until #{format_date(valid_until)}"

      match?(%DateTime{}, valid_from) ->
        "Valid from #{format_date(valid_from)}"

      true ->
        nil
    end
  end

  defp format_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %d, %Y")
  end

  defp format_date(_dt), do: nil

  defp validity_classes("Expired"),
    do: "border-[color:var(--danger)] bg-[color:var(--bg-base)] text-[color:var(--danger)]"

  defp validity_classes("Not yet valid"),
    do: "border-[color:var(--warning)] bg-[color:var(--bg-base)] text-[color:var(--warning)]"

  defp validity_classes(_status),
    do: "border-[color:var(--success)] bg-[color:var(--bg-base)] text-[color:var(--success)]"

  defp badge_path(%User{} = user, %Object{id: id}) do
    badge_id = id |> to_string() |> String.trim()

    if badge_id == "" do
      nil
    else
      case badges_path(user) do
        path when is_binary(path) -> path <> "/" <> badge_id
        _ -> nil
      end
    end
  end

  defp badge_path(_user, _accept), do: nil

  defp badges_path(%User{} = user) do
    case ProfilePaths.profile_path(user) do
      path when is_binary(path) and path != "" -> path <> "/badges"
      _ -> nil
    end
  end

  defp badges_path(_user), do: nil

  defp fetch_badge(%User{} = user, badge_id) when is_binary(badge_id) do
    badge_id = String.trim(badge_id)

    cond do
      badge_id == "" ->
        nil

      true ->
        badge =
          direct_badge_from_id(user, badge_id) ||
            find_badge_in_recent_accepts(user, badge_id)

        badge
    end
  end

  defp fetch_badge(_user, _badge_id), do: nil

  defp direct_badge_from_id(%User{} = user, badge_id) when is_binary(badge_id) do
    accept = Objects.get(badge_id) || Objects.get_by_ap_id(badge_id)

    case accept do
      %Object{type: "Accept", actor: actor} = accept when actor == user.ap_id ->
        badge_entry(accept, user)

      %Object{type: "VerifiableCredential"} = credential ->
        badge_entry_from_credential(credential, user)

      _ ->
        nil
    end
  end

  defp direct_badge_from_id(_user, _badge_id), do: nil

  defp find_badge_in_recent_accepts(%User{} = user, badge_id) when is_binary(badge_id) do
    user
    |> list_accepts(limit: 200)
    |> decorate_badges(user)
    |> Enum.find(fn
      %{accept: %Object{id: id, ap_id: ap_id}} ->
        badge_id == to_string(id) or
          (is_binary(ap_id) and String.trim(ap_id) == badge_id)

      _ ->
        false
    end)
  end

  defp find_badge_in_recent_accepts(_user, _badge_id), do: nil

  defp badges_cursor([]), do: nil

  defp badges_cursor(accepts) when is_list(accepts) do
    case List.last(accepts) do
      %Object{id: id} -> id
      _ -> nil
    end
  end

  defp badge_dom_id(%{accept: %Object{id: id}}), do: "badge-#{id}"
  defp badge_dom_id(_badge), do: "badge-#{Ecto.UUID.generate()}"

  defp notifications_count(nil), do: 0

  defp notifications_count(%User{} = user) do
    user
    |> Notifications.list_for_user(limit: @page_size, include_offers?: true)
    |> length()
  end
end
