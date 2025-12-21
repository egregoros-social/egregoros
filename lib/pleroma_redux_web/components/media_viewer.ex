defmodule PleromaReduxWeb.MediaViewer do
  use PleromaReduxWeb, :html

  alias PleromaRedux.Objects
  alias PleromaReduxWeb.Attachments
  alias PleromaReduxWeb.ViewModels.Status, as: StatusVM

  def open(socket, %{"id" => id, "index" => index}, current_user) do
    with {post_id, ""} <- Integer.parse(to_string(id)),
         {index, ""} <- Integer.parse(to_string(index)),
         %{} = post <- Objects.get(post_id) do
      entry = StatusVM.decorate(post, current_user)

      {items, selected_index} = media_items(entry.attachments, index)

      case Enum.at(items, selected_index) do
        %{href: href} when is_binary(href) and href != "" ->
          Phoenix.Component.assign(socket, :media_viewer, %{
            post_id: post_id,
            index: selected_index,
            items: items
          })

        _ ->
          socket
      end
    else
      _ -> socket
    end
  end

  def close(socket) do
    Phoenix.Component.assign(socket, :media_viewer, nil)
  end

  def handle_keydown(socket, %{"key" => key}) when is_binary(key) do
    case key do
      "Escape" -> close(socket)
      "Esc" -> close(socket)
      "ArrowRight" -> next(socket)
      "ArrowLeft" -> prev(socket)
      _ -> socket
    end
  end

  def handle_keydown(socket, _params), do: socket

  def next(socket) do
    bump_index(socket, 1)
  end

  def prev(socket) do
    bump_index(socket, -1)
  end

  attr :viewer, :map, required: true

  def media_viewer(assigns) do
    assigns =
      assigns
      |> assign_new(:item, fn ->
        Enum.at(Map.get(assigns.viewer, :items, []), Map.get(assigns.viewer, :index, 0))
      end)
      |> assign_new(:item_count, fn -> assigns.viewer |> Map.get(:items, []) |> length() end)

    ~H"""
    <div
      id="media-viewer"
      data-role="media-viewer"
      role="dialog"
      aria-modal="true"
      phx-mounted={
        JS.push_focus()
        |> JS.focus(to: "#media-viewer [data-role='media-viewer-close']")
      }
      phx-remove={JS.pop_focus()}
      phx-window-keydown="media_keydown"
      class="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/70 p-4 backdrop-blur"
    >
      <.focus_wrap
        id="media-viewer-dialog"
        phx-click-away="close_media"
        class="relative w-full max-w-4xl overflow-hidden rounded-3xl bg-black shadow-2xl"
      >
        <button
          :if={@item_count > 1}
          type="button"
          data-role="media-viewer-prev"
          phx-click="media_prev"
          class="absolute left-4 top-1/2 -translate-y-1/2 inline-flex h-10 w-10 items-center justify-center rounded-2xl bg-white/10 text-white transition hover:bg-white/20 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/60"
          aria-label="Previous media"
        >
          <.icon name="hero-chevron-left" class="size-5" />
        </button>

        <button
          type="button"
          data-role="media-viewer-close"
          phx-click="close_media"
          class="absolute right-4 top-4 inline-flex h-10 w-10 items-center justify-center rounded-2xl bg-white/10 text-white transition hover:bg-white/20 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/60"
          aria-label="Close media viewer"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>

        <button
          :if={@item_count > 1}
          type="button"
          data-role="media-viewer-next"
          phx-click="media_next"
          class="absolute right-4 top-1/2 -translate-y-1/2 inline-flex h-10 w-10 items-center justify-center rounded-2xl bg-white/10 text-white transition hover:bg-white/20 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/60"
          aria-label="Next media"
        >
          <.icon name="hero-chevron-right" class="size-5" />
        </button>

        <%= if @item do %>
          <%= case Attachments.kind(@item) do %>
            <% :video -> %>
              <video
                data-role="media-viewer-item"
                controls
                preload="metadata"
                playsinline
                class="max-h-[85vh] w-full bg-black"
                aria-label={Map.get(@item, :description, "Video attachment")}
              >
                <source src={@item.href} type={Attachments.source_type(@item, "video/mp4")} />
              </video>
            <% :audio -> %>
              <div class="flex max-h-[85vh] w-full items-center justify-center bg-black/90 px-6 py-10">
                <audio
                  data-role="media-viewer-item"
                  controls
                  preload="metadata"
                  class="w-full"
                  aria-label={Map.get(@item, :description, "Audio attachment")}
                >
                  <source src={@item.href} type={Attachments.source_type(@item, "audio/mpeg")} />
                </audio>
              </div>
            <% _ -> %>
              <img
                data-role="media-viewer-item"
                src={@item.href}
                alt={Map.get(@item, :description, "")}
                class="max-h-[85vh] w-full object-contain"
                loading="lazy"
              />
          <% end %>
        <% end %>
      </.focus_wrap>
    </div>
    """
  end

  defp bump_index(%{assigns: %{media_viewer: %{items: items, index: index} = viewer}} = socket, delta) do
    count = length(items)

    cond do
      count < 2 ->
        socket

      true ->
        new_index = rem(index + delta + count, count)
        Phoenix.Component.assign(socket, :media_viewer, %{viewer | index: new_index})
    end
  end

  defp bump_index(socket, _delta), do: socket

  defp media_items(attachments, selected_index)
       when is_list(attachments) and is_integer(selected_index) do
    media =
      attachments
      |> Enum.with_index()
      |> Enum.filter(fn {attachment, _index} -> Attachments.media?(attachment) end)

    items = Enum.map(media, &elem(&1, 0))

    selected_index =
      case Enum.find_index(media, fn {_attachment, original_index} -> original_index == selected_index end) do
        nil -> 0
        index -> index
      end

    {items, selected_index}
  end

  defp media_items(_attachments, _selected_index), do: {[], 0}
end
