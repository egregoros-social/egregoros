defmodule EgregorosWeb.ReplyModal do
  use EgregorosWeb, :html

  @moduledoc false

  attr :id, :string, default: "reply-modal"
  attr :form_id, :string, default: "reply-modal-form"
  attr :id_prefix, :string, default: "reply-modal"
  attr :open, :boolean, default: false

  attr :form, :any, required: true
  attr :upload, :any, required: true
  attr :media_alt, :map, default: %{}

  attr :reply_to_handle, :string, default: nil

  attr :mention_suggestions, :map, default: %{}

  attr :max_chars, :integer, default: 5000
  attr :options_open?, :boolean, default: false
  attr :cw_open?, :boolean, default: false

  attr :change_event, :string, default: "reply_change"
  attr :submit_event, :string, default: "create_reply"
  attr :cancel_event, :string, default: "cancel_reply_media"
  attr :toggle_cw_event, :string, default: "toggle_reply_cw"
  attr :close_event, :string, default: "close_reply_modal"

  def reply_modal(assigns) do
    ~H"""
    <div
      id={@id}
      data-role="reply-modal"
      data-state={if @open, do: "open", else: "closed"}
      role="dialog"
      aria-modal="true"
      aria-hidden={if @open, do: "false", else: "true"}
      phx-hook="ReplyModal"
      class={[
        "fixed inset-0 z-50 flex items-center justify-center bg-slate-950/60 p-4 backdrop-blur",
        !@open && "hidden"
      ]}
    >
      <.focus_wrap
        id={"#{@id}-dialog"}
        phx-click-away={close_js(@id, @close_event)}
        class="relative w-full max-w-2xl overflow-visible rounded-3xl border border-white/80 bg-white/95 p-6 shadow-2xl shadow-slate-900/20 dark:border-slate-700/70 dark:bg-slate-950/80 dark:shadow-slate-900/50"
      >
        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <p class="text-xs font-semibold uppercase tracking-[0.3em] text-slate-500 dark:text-slate-400">
              Reply
            </p>

            <p
              :if={is_binary(@reply_to_handle) and @reply_to_handle != ""}
              data-role="reply-modal-target"
              class="mt-2 truncate text-sm font-semibold text-slate-800 dark:text-slate-100"
            >
              Replying to {@reply_to_handle}
            </p>
          </div>

          <.icon_button
            data-role="reply-modal-close"
            phx-click={close_js(@id, @close_event)}
            label="Close reply composer"
            class="shrink-0"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </.icon_button>
        </div>

        <Composer.composer_form
          id={@form_id}
          id_prefix={@id_prefix}
          form={@form}
          upload={@upload}
          media_alt={@media_alt}
          mention_suggestions={Map.get(@mention_suggestions, @id_prefix, [])}
          param_prefix="reply"
          max_chars={@max_chars}
          options_open?={@options_open?}
          cw_open?={@cw_open?}
          change_event={@change_event}
          submit_event={@submit_event}
          cancel_event={@cancel_event}
          toggle_cw_event={@toggle_cw_event}
          submit_label="Reply"
          class="mt-0"
        />
      </.focus_wrap>
    </div>
    """
  end

  defp close_js(id, close_event) when is_binary(id) and is_binary(close_event) do
    JS.dispatch("egregoros:reply-close", to: "##{id}")
    |> JS.push(close_event)
  end
end
