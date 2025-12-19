defmodule PleromaReduxWeb.TimelineLive do
  use PleromaReduxWeb, :live_view

  alias PleromaRedux.Federation
  alias PleromaRedux.Timeline
  alias PleromaRedux.Users

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      Timeline.subscribe()
    end

    current_user =
      case Map.get(session, "user_id") do
        nil -> nil
        id -> Users.get(id)
      end

    form = Phoenix.Component.to_form(%{"content" => ""}, as: :post)
    follow_form = Phoenix.Component.to_form(%{"handle" => ""}, as: :follow)

    {:ok,
     assign(socket,
       posts: Timeline.list_posts(),
       error: nil,
       follow_error: nil,
       follow_success: nil,
       form: form,
       follow_form: follow_form,
       current_user: current_user
     )}
  end

  @impl true
  def handle_event("create_post", %{"post" => %{"content" => content}}, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, assign(socket, error: "Register to post.")}

      user ->
        case Timeline.create_post(user, content) do
          {:ok, _post} ->
            {:noreply,
             assign(socket, form: Phoenix.Component.to_form(%{"content" => ""}, as: :post), error: nil)}

          {:error, :empty} ->
            {:noreply,
             assign(socket,
               error: "Post can't be empty.",
               form: Phoenix.Component.to_form(%{"content" => content}, as: :post)
             )}
        end
    end
  end

  def handle_event("follow_remote", %{"follow" => %{"handle" => handle}}, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, assign(socket, follow_error: "Register to follow people.", follow_success: nil)}

      user ->
        case Federation.follow_remote(user, handle) do
          {:ok, remote} ->
            {:noreply,
             assign(socket,
               follow_form: Phoenix.Component.to_form(%{"handle" => ""}, as: :follow),
               follow_error: nil,
               follow_success: "Following #{remote.ap_id}."
             )}

          {:error, _reason} ->
            {:noreply, assign(socket, follow_error: "Could not follow.", follow_success: nil)}
        end
    end
  end

  @impl true
  def handle_info({:post_created, post}, socket) do
    {:noreply, update(socket, :posts, fn posts -> [post | posts] end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <section class="grid gap-6">
        <div class="rounded-3xl border border-white/80 bg-white/80 p-6 shadow-xl shadow-slate-200/40 backdrop-blur dark:border-slate-700/60 dark:bg-slate-900/70 dark:shadow-slate-900/40 animate-rise">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-xs uppercase tracking-[0.3em] text-slate-500 dark:text-slate-400">Compose</p>
              <h2 class="mt-2 font-display text-xl text-slate-900 dark:text-slate-100">
                Broadcast a short note
              </h2>
            </div>
            <div class="hidden text-right text-xs text-slate-500 dark:text-slate-400 sm:block">
              Live timeline updates
            </div>
          </div>

          <.form
            for={@follow_form}
            id="follow-form"
            phx-submit="follow_remote"
            class="mt-6 flex flex-col gap-4 sm:flex-row sm:items-end"
          >
            <div class="flex-1">
              <.input
                type="text"
                field={@follow_form[:handle]}
                label="Follow"
                placeholder="bob@remote.example"
                class="w-full rounded-2xl border border-slate-200/80 bg-white/70 px-4 py-3 text-sm text-slate-900 outline-none transition focus:border-slate-400 focus:ring-2 focus:ring-slate-200 dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-100 dark:focus:border-slate-400 dark:focus:ring-slate-600"
              />
            </div>

            <button
              type="submit"
              class="rounded-full border border-slate-200/80 bg-white/70 px-5 py-3 text-sm font-semibold text-slate-700 transition hover:-translate-y-0.5 hover:bg-white dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:hover:bg-slate-950"
            >
              Follow
            </button>
          </.form>

          <p :if={@follow_error} class="mt-3 text-sm text-rose-500"><%= @follow_error %></p>
          <p :if={@follow_success} class="mt-3 text-sm text-emerald-600 dark:text-emerald-400">
            <%= @follow_success %>
          </p>

          <.form for={@form} id="timeline-form" phx-submit="create_post" class="mt-6 space-y-4">
            <.input
              type="textarea"
              field={@form[:content]}
              placeholder="What's happening?"
              rows="3"
              phx-debounce="blur"
              class="w-full resize-none rounded-2xl border border-slate-200/80 bg-white/70 px-4 py-3 text-sm text-slate-900 outline-none transition focus:border-slate-400 focus:ring-2 focus:ring-slate-200 dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-100 dark:focus:border-slate-400 dark:focus:ring-slate-600"
            />

            <div class="flex flex-wrap items-center justify-between gap-3">
              <p :if={@error} class="text-sm text-rose-500"><%= @error %></p>
              <div class="ml-auto flex items-center gap-3">
                <span class="text-xs uppercase tracking-[0.25em] text-slate-400 dark:text-slate-500">
                  <%= if @current_user, do: @current_user.nickname, else: "guest" %>
                </span>
                <button
                  type="submit"
                  class="rounded-full bg-slate-900 px-5 py-2 text-sm font-semibold text-white shadow-lg shadow-slate-900/20 transition hover:-translate-y-0.5 hover:bg-slate-800 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-white"
                >
                  Post
                </button>
              </div>
            </div>
          </.form>
        </div>

        <section class="space-y-4">
          <%= for {post, idx} <- Enum.with_index(@posts) do %>
            <article
              class="rounded-3xl border border-white/80 bg-white/80 p-6 shadow-lg shadow-slate-200/30 backdrop-blur transition hover:-translate-y-0.5 hover:shadow-xl dark:border-slate-700/60 dark:bg-slate-900/70 dark:shadow-slate-900/50 animate-rise"
              style={"animation-delay: #{idx * 45}ms"}
            >
              <div class="flex items-start justify-between">
                <div>
                  <p class="text-xs uppercase tracking-[0.25em] text-slate-500 dark:text-slate-400">
                    local
                  </p>
                  <p class="mt-3 text-base leading-relaxed text-slate-900 dark:text-slate-100">
                    <%= post.data["content"] %>
                  </p>
                </div>
                <span class="text-xs text-slate-400 dark:text-slate-500"><%= format_time(post.inserted_at) %></span>
              </div>
            </article>
          <% end %>
        </section>
      </section>
    </Layouts.app>
    """
  end

  defp format_time(%DateTime{} = dt) do
    dt
    |> DateTime.to_naive()
    |> NaiveDateTime.truncate(:second)
    |> NaiveDateTime.to_string()
  end

  defp format_time(%NaiveDateTime{} = dt) do
    dt
    |> NaiveDateTime.truncate(:second)
    |> NaiveDateTime.to_string()
  end
end
