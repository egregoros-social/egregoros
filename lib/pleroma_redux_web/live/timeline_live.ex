defmodule PleromaReduxWeb.TimelineLive do
  use PleromaReduxWeb, :live_view

  alias PleromaRedux.Timeline

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Timeline.subscribe()
    end

    {:ok, assign(socket, posts: Timeline.list_posts(), error: nil, content: "")}
  end

  @impl true
  def handle_event("create_post", %{"content" => content}, socket) do
    case Timeline.create_post(content) do
      {:ok, _post} ->
        {:noreply, assign(socket, content: "", error: nil)}

      {:error, :empty} ->
        {:noreply, assign(socket, error: "Post can't be empty.")}
    end
  end

  @impl true
  def handle_info({:post_created, post}, socket) do
    {:noreply, update(socket, :posts, fn posts -> [post | posts] end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl px-6 py-10">
      <header class="mb-8">
        <p class="text-xs uppercase tracking-[0.2em] text-zinc-500">Pleroma Redux</p>
        <h1 class="mt-2 text-3xl font-semibold text-zinc-900">Timeline</h1>
        <p class="mt-2 text-sm text-zinc-600">Live updates without refresh.</p>
      </header>

      <section class="mb-8 rounded-2xl border border-zinc-200 bg-white p-5 shadow-sm">
        <form phx-submit="create_post" class="space-y-4">
          <textarea
            name="content"
            rows="3"
            class="w-full resize-none rounded-xl border border-zinc-300 px-4 py-3 text-sm text-zinc-900 focus:border-zinc-500 focus:outline-none"
            placeholder="What's happening?"
            phx-debounce="blur"
          ><%= @content %></textarea>

          <div class="flex items-center justify-between">
            <p class="text-sm text-rose-600"><%= @error %></p>
            <button
              type="submit"
              class="rounded-full bg-zinc-900 px-4 py-2 text-sm font-semibold text-white hover:bg-zinc-800"
            >
              Post
            </button>
          </div>
        </form>
      </section>

      <section class="space-y-4">
        <%= for post <- @posts do %>
          <article class="rounded-2xl border border-zinc-200 bg-white p-5 shadow-sm">
            <p class="text-sm text-zinc-900"><%= post.data["content"] %></p>
            <p class="mt-2 text-xs text-zinc-500"><%= format_time(post.inserted_at) %></p>
          </article>
        <% end %>
      </section>
    </div>
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
