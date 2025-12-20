defmodule PleromaReduxWeb.MediaViewer do
  use PleromaReduxWeb, :html

  alias PleromaRedux.Objects
  alias PleromaReduxWeb.ViewModels.Status, as: StatusVM

  def open(socket, %{"id" => id, "index" => index}, current_user) do
    with {post_id, ""} <- Integer.parse(to_string(id)),
         {index, ""} <- Integer.parse(to_string(index)),
         %{} = post <- Objects.get(post_id) do
      entry = StatusVM.decorate(post, current_user)

      case Enum.at(entry.attachments, index) do
        %{href: href} = attachment when is_binary(href) and href != "" ->
          description = Map.get(attachment, :description) || ""

          Phoenix.Component.assign(socket, :media_viewer, %{
            src: href,
            alt: to_string(description),
            post_id: post_id,
            index: index
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

  attr :viewer, :map, required: true

  def media_viewer(assigns) do
    ~H"""
    <div
      data-role="media-viewer"
      role="dialog"
      aria-modal="true"
      class="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/70 p-4 backdrop-blur"
    >
      <div class="relative w-full max-w-4xl overflow-hidden rounded-3xl bg-black shadow-2xl">
        <button
          type="button"
          data-role="media-viewer-close"
          phx-click="close_media"
          class="absolute right-4 top-4 inline-flex h-10 w-10 items-center justify-center rounded-2xl bg-white/10 text-white transition hover:bg-white/20 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/60"
          aria-label="Close media viewer"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>

        <img
          src={@viewer.src}
          alt={@viewer.alt}
          class="max-h-[85vh] w-full object-contain"
          loading="lazy"
        />
      </div>
    </div>
    """
  end
end
