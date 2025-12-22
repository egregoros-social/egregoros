defmodule PleromaReduxWeb.MediaViewer do
  use PleromaReduxWeb, :html

  alias PleromaReduxWeb.Attachments

  attr :viewer, :map, required: true
  attr :open, :boolean, default: false

  def media_viewer(assigns) do
    items = Map.get(assigns.viewer, :items, [])
    index = Map.get(assigns.viewer, :index, 0)

    assigns =
      assigns
      |> assign(:items, items)
      |> assign(:index, index)
      |> assign(:item_count, length(items))

    ~H"""
    <div
      id="media-viewer"
      data-role="media-viewer"
      data-state={if @open, do: "open", else: "closed"}
      data-index={@index}
      data-count={@item_count}
      role="dialog"
      aria-modal="true"
      aria-hidden={if @open, do: "false", else: "true"}
      phx-hook="MediaViewer"
      class={[
        "fixed inset-0 z-50 flex items-center justify-center bg-slate-950/70 p-4 backdrop-blur",
        !@open && "hidden"
      ]}
    >
      <.focus_wrap
        id="media-viewer-dialog"
        phx-click-away={JS.dispatch("predux:media-close", to: "#media-viewer")}
        class="relative w-full max-w-4xl overflow-hidden rounded-3xl bg-black shadow-2xl"
      >
        <button
          type="button"
          data-role="media-viewer-prev"
          phx-click={JS.dispatch("predux:media-prev", to: "#media-viewer")}
          class={[
            "absolute left-4 top-1/2 z-20 -translate-y-1/2 inline-flex h-10 w-10 items-center justify-center rounded-2xl bg-white/10 text-white transition hover:bg-white/20 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/60",
            @item_count < 2 && "hidden"
          ]}
          aria-label="Previous media"
        >
          <.icon name="hero-chevron-left" class="size-5" />
        </button>

        <button
          type="button"
          data-role="media-viewer-close"
          phx-click={JS.dispatch("predux:media-close", to: "#media-viewer")}
          class="absolute right-4 top-4 z-20 inline-flex h-10 w-10 items-center justify-center rounded-2xl bg-white/10 text-white transition hover:bg-white/20 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/60"
          aria-label="Close media viewer"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>

        <button
          type="button"
          data-role="media-viewer-next"
          phx-click={JS.dispatch("predux:media-next", to: "#media-viewer")}
          class={[
            "absolute right-4 top-1/2 z-20 -translate-y-1/2 inline-flex h-10 w-10 items-center justify-center rounded-2xl bg-white/10 text-white transition hover:bg-white/20 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/60",
            @item_count < 2 && "hidden"
          ]}
          aria-label="Next media"
        >
          <.icon name="hero-chevron-right" class="size-5" />
        </button>

        <div data-role="media-viewer-slides" class="relative">
          <div
            :for={{item, idx} <- Enum.with_index(@items)}
            data-role="media-viewer-slide"
            data-index={idx}
            data-state={if idx == @index, do: "active", else: "inactive"}
            aria-hidden={if idx == @index, do: "false", else: "true"}
            class={[
              "w-full",
              idx != @index && "hidden"
            ]}
          >
            <%= case Attachments.kind(item) do %>
              <% :video -> %>
                <video
                  data-role="media-viewer-item"
                  controls
                  preload="metadata"
                  playsinline
                  class="max-h-[85vh] w-full bg-black"
                  aria-label={Map.get(item, :description, "Video attachment")}
                >
                  <source src={item.href} type={Attachments.source_type(item, "video/mp4")} />
                </video>
              <% :audio -> %>
                <div class="flex max-h-[85vh] w-full items-center justify-center bg-black/90 px-6 py-10">
                  <audio
                    data-role="media-viewer-item"
                    controls
                    preload="metadata"
                    class="w-full"
                    aria-label={Map.get(item, :description, "Audio attachment")}
                  >
                    <source src={item.href} type={Attachments.source_type(item, "audio/mpeg")} />
                  </audio>
                </div>
              <% _ -> %>
                <img
                  data-role="media-viewer-item"
                  src={item.href}
                  alt={Map.get(item, :description, "")}
                  class="max-h-[85vh] w-full object-contain"
                  loading="lazy"
                />
            <% end %>
          </div>
        </div>
      </.focus_wrap>
    </div>
    """
  end
end
