defmodule PleromaReduxWeb.Composer do
  use PleromaReduxWeb, :html

  @moduledoc false

  attr :id, :string, required: true
  attr :form, :any, required: true
  attr :upload, :any, required: true
  attr :media_alt, :map, default: %{}
  attr :param_prefix, :string, required: true
  attr :id_prefix, :string, required: true
  attr :class, :string, default: nil
  attr :rest, :global

  attr :change_event, :string, required: true
  attr :submit_event, :string, required: true
  attr :cancel_event, :string, required: true
  attr :toggle_cw_event, :string, required: true

  attr :max_chars, :integer, default: 5000
  attr :options_open?, :boolean, default: false
  attr :cw_open?, :boolean, default: false
  attr :error, :string, default: nil
  attr :submit_label, :string, default: "Post"

  slot :extra_fields

  def composer_form(assigns) do
    assigns =
      assigns
      |> assign_new(:options_state_id, fn -> "#{assigns.id_prefix}-options-state" end)
      |> assign_new(:cw_id, fn -> "#{assigns.id_prefix}-cw" end)
      |> assign_new(:options_id, fn -> "#{assigns.id_prefix}-options" end)
      |> assign_new(:emoji_picker_id, fn -> "#{assigns.id_prefix}-emoji-picker" end)
      |> assign_new(:media_input_id, fn -> "#{assigns.id_prefix}-media-input" end)
      |> assign_new(:content_id, fn -> "#{assigns.id_prefix}-content" end)

    ~H"""
    <.form
      for={@form}
      id={@id}
      phx-change={@change_event}
      phx-submit={@submit_event}
      class={["mt-6 space-y-3", @class]}
      {@rest}
    >
      <.input
        type="hidden"
        id={@options_state_id}
        name={"#{@param_prefix}[ui_options_open]"}
        value={Map.get(@form.params || %{}, "ui_options_open", "false")}
        data-role="compose-options-state"
      />

      {render_slot(@extra_fields)}

      <div
        data-role="compose-editor"
        phx-drop-target={@upload.ref}
        class="overflow-hidden rounded-2xl border border-slate-200/80 bg-white/70 shadow-sm shadow-slate-200/20 transition focus-within:border-slate-400 focus-within:ring-2 focus-within:ring-slate-200 dark:border-slate-700/80 dark:bg-slate-950/60 dark:shadow-slate-900/30 dark:focus-within:border-slate-400 dark:focus-within:ring-slate-600"
      >
        <div class="flex flex-wrap gap-2 px-4 pt-4">
          <button
            type="button"
            data-role="compose-visibility-pill"
            phx-click={toggle_options_js(@options_id, @options_state_id)}
            class="inline-flex items-center gap-2 rounded-xl border border-slate-200/80 bg-white/70 px-3 py-2 text-xs font-semibold text-slate-700 transition hover:bg-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:hover:bg-slate-950"
            aria-label="Post visibility"
          >
            <.icon name="hero-globe-alt" class="size-4 opacity-80" />
            {visibility_label(Map.get(@form.params || %{}, "visibility"))}
          </button>

          <button
            type="button"
            data-role="compose-language-pill"
            phx-click={toggle_options_js(@options_id, @options_state_id)}
            class="inline-flex items-center gap-2 rounded-xl border border-slate-200/80 bg-white/70 px-3 py-2 text-xs font-semibold text-slate-700 transition hover:bg-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:hover:bg-slate-950"
            aria-label="Post language"
          >
            <.icon name="hero-language" class="size-4 opacity-80" />
            {language_label(Map.get(@form.params || %{}, "language"))}
          </button>
        </div>

        <div
          id={@cw_id}
          data-role="compose-cw"
          data-state={if @cw_open?, do: "open", else: "closed"}
          class={["px-4 pt-3", !@cw_open? && "hidden"]}
        >
          <.input
            type="text"
            field={@form[:spoiler_text]}
            placeholder="Content warning"
            phx-debounce="blur"
            class="w-full rounded-xl border border-slate-200/80 bg-white/70 px-3 py-2 text-sm text-slate-900 outline-none transition focus:border-slate-400 focus:ring-2 focus:ring-slate-200 dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-100 dark:focus:border-slate-400 dark:focus:ring-slate-600"
          />
        </div>

        <div class="px-4 pb-4 pt-3">
          <.input
            type="textarea"
            id={@content_id}
            field={@form[:content]}
            data-role="compose-content"
            data-max-chars={@max_chars}
            phx-hook="ComposeCharCounter"
            placeholder="What's on your mind?"
            rows="6"
            phx-debounce="blur"
            class="min-h-[7rem] w-full resize-none border-0 bg-transparent p-0 text-base leading-6 text-slate-900 outline-none placeholder:text-slate-400 focus:ring-0 dark:text-slate-100 dark:placeholder:text-slate-500"
          />
        </div>

        <div
          id={@options_id}
          data-role="compose-options"
          data-state={if @options_open?, do: "open", else: "closed"}
          class={[
            "border-t border-slate-200/70 bg-white/60 px-4 py-4 dark:border-slate-700/70 dark:bg-slate-950/40",
            !@options_open? && "hidden"
          ]}
        >
          <div class="grid gap-4">
            <.input
              type="select"
              field={@form[:visibility]}
              label="Visibility"
              options={[
                Public: "public",
                Unlisted: "unlisted",
                Private: "private",
                Direct: "direct"
              ]}
            />

            <.input
              type="text"
              field={@form[:language]}
              label="Language"
              placeholder="Optional (e.g. en)"
              phx-debounce="blur"
            />

            <.input
              type="checkbox"
              field={@form[:sensitive]}
              label="Mark media as sensitive"
            />
          </div>
        </div>

        <div
          :if={@upload.entries != [] or upload_errors(@upload) != []}
          data-role="compose-media"
          class="border-t border-slate-200/70 bg-white/60 px-4 py-4 dark:border-slate-700/70 dark:bg-slate-950/40"
        >
          <div class="grid gap-3">
            <div
              :for={entry <- @upload.entries}
              id={"#{@id_prefix}-media-entry-#{entry.ref}"}
              data-role="media-entry"
              class="rounded-2xl border border-slate-200/80 bg-white/60 p-3 shadow-sm shadow-slate-200/20 dark:border-slate-700/70 dark:bg-slate-950/50 dark:shadow-slate-900/40"
            >
              <div class="flex gap-3">
                <div class="relative h-16 w-16 overflow-hidden rounded-2xl border border-slate-200/80 bg-white shadow-sm shadow-slate-200/20 dark:border-slate-700/70 dark:bg-slate-950/60 dark:shadow-slate-900/40">
                  <.upload_entry_preview entry={entry} />
                </div>

                <div class="min-w-0 flex-1 space-y-3">
                  <div class="flex items-start justify-between gap-3">
                    <p class="truncate text-sm font-semibold text-slate-800 dark:text-slate-100">
                      {entry.client_name}
                    </p>
                    <button
                      type="button"
                      phx-click={@cancel_event}
                      phx-value-ref={entry.ref}
                      class="inline-flex h-9 w-9 items-center justify-center rounded-2xl text-slate-500 transition hover:bg-slate-900/5 hover:text-slate-900 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:text-slate-300 dark:hover:bg-white/10 dark:hover:text-white"
                      aria-label="Remove attachment"
                    >
                      <.icon name="hero-x-mark" class="size-4" />
                    </button>
                  </div>

                  <div class="h-2 overflow-hidden rounded-full bg-slate-200/70 dark:bg-slate-700/50">
                    <div
                      class="h-full bg-slate-900 transition-all dark:bg-slate-100"
                      style={"width: #{entry.progress}%"}
                    >
                    </div>
                  </div>
                  <span class="sr-only" data-role="media-progress">{entry.progress}%</span>

                  <details
                    :if={upload_entry_kind(entry) in [:video, :audio]}
                    class="rounded-2xl border border-slate-200/80 bg-white/70 px-4 py-3 dark:border-slate-700/70 dark:bg-slate-950/50"
                  >
                    <summary class="cursor-pointer select-none text-xs font-semibold uppercase tracking-[0.2em] text-slate-600 dark:text-slate-300 list-none [&::-webkit-details-marker]:hidden">
                      Preview
                    </summary>
                    <div class="mt-3">
                      <.upload_entry_player entry={entry} />
                    </div>
                  </details>

                  <.input
                    type="text"
                    id={"#{@id_prefix}-media-alt-#{entry.ref}"}
                    name={"#{@param_prefix}[media_alt][#{entry.ref}]"}
                    label="Alt text"
                    value={Map.get(@media_alt, entry.ref, "")}
                    placeholder={upload_entry_description_placeholder(entry)}
                    phx-debounce="blur"
                  />

                  <p
                    :for={err <- upload_errors(@upload, entry)}
                    data-role="upload-error"
                    class="text-sm text-rose-600 dark:text-rose-400"
                  >
                    {upload_error_text(err)}
                  </p>
                </div>
              </div>
            </div>
          </div>

          <p
            :for={err <- upload_errors(@upload)}
            data-role="upload-error"
            class="mt-3 text-sm text-rose-600 dark:text-rose-400"
          >
            {upload_error_text(err)}
          </p>
        </div>

        <div
          data-role="compose-toolbar"
          class="flex flex-wrap items-center justify-between gap-3 border-t border-slate-200/70 bg-white/70 px-4 py-3 dark:border-slate-700/70 dark:bg-slate-950/50"
        >
          <div class="flex items-center gap-1">
            <label
              data-role="compose-add-media"
              aria-label="Add media"
              class="relative inline-flex h-10 w-10 cursor-pointer items-center justify-center rounded-2xl text-slate-500 transition hover:bg-slate-900/5 hover:text-slate-900 focus-within:outline-none focus-within:ring-2 focus-within:ring-slate-400 dark:text-slate-300 dark:hover:bg-white/10 dark:hover:text-white"
            >
              <.icon name="hero-photo" class="size-5" />
              <span class="sr-only">Add media</span>
              <.live_file_input
                upload={@upload}
                id={@media_input_id}
                class="absolute inset-0 h-full w-full cursor-pointer opacity-0"
              />
            </label>

            <button
              type="button"
              data-role="compose-toggle-cw"
              phx-click={toggle_cw_js(@cw_id) |> JS.push(@toggle_cw_event)}
              aria-label="Content warning"
              class={[
                "inline-flex h-10 w-10 items-center justify-center rounded-2xl transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400",
                @cw_open? &&
                  "bg-rose-600/10 text-rose-700 hover:bg-rose-600/15 dark:bg-rose-400/10 dark:text-rose-200 dark:hover:bg-rose-400/15",
                !@cw_open? &&
                  "text-slate-500 hover:bg-slate-900/5 hover:text-slate-900 dark:text-slate-300 dark:hover:bg-white/10 dark:hover:text-white"
              ]}
            >
              <.icon name="hero-exclamation-triangle" class="size-5" />
            </button>

            <button
              type="button"
              data-role="compose-toggle-options"
              phx-click={toggle_options_js(@options_id, @options_state_id)}
              aria-label="Post options"
              class={[
                "inline-flex h-10 w-10 items-center justify-center rounded-2xl transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400",
                @options_open? &&
                  "bg-slate-900/5 text-slate-900 dark:bg-white/10 dark:text-white",
                !@options_open? &&
                  "text-slate-500 hover:bg-slate-900/5 hover:text-slate-900 dark:text-slate-300 dark:hover:bg-white/10 dark:hover:text-white"
              ]}
            >
              <.icon name="hero-adjustments-horizontal" class="size-5" />
            </button>

            <.compose_emoji_picker id={@emoji_picker_id} />
          </div>

          <% remaining = remaining_chars(@form, @max_chars) %>

          <div class="flex items-center gap-3">
            <div class="flex flex-col items-end gap-1 text-right">
              <span
                data-role="compose-char-counter"
                class={[
                  "tabular-nums text-sm font-semibold",
                  remaining < 0 && "text-rose-600 dark:text-rose-400",
                  remaining >= 0 && "text-slate-500 dark:text-slate-400"
                ]}
              >
                {remaining}
              </span>

              <span
                :if={remaining < 0}
                data-role="compose-char-error"
                class="text-xs font-semibold text-rose-600 dark:text-rose-400"
              >
                Too long by {abs(remaining)} character{if abs(remaining) == 1, do: "", else: "s"}.
              </span>
            </div>

            <.button
              data-role="compose-submit"
              type="submit"
              phx-disable-with="Posting..."
              disabled={submit_disabled?(@form, @upload, @max_chars)}
              size="sm"
              class="normal-case tracking-normal"
            >
              {@submit_label}
            </.button>
          </div>
        </div>
      </div>

      <p :if={@error} data-role="compose-error" class="text-sm text-rose-500">
        {@error}
      </p>
    </.form>
    """
  end

  defp toggle_options_js(options_id, options_state_id) when is_binary(options_id) do
    JS.toggle_class("hidden", to: "##{options_id}")
    |> JS.toggle_attribute({"value", "true", "false"}, to: "##{options_state_id}")
  end

  defp toggle_cw_js(cw_id) when is_binary(cw_id) do
    JS.toggle_class("hidden", to: "##{cw_id}")
  end

  defp remaining_chars(%Phoenix.HTML.Form{} = form, max_chars) when is_integer(max_chars) do
    max_chars - String.length(content_value(form))
  end

  defp remaining_chars(_form, max_chars) when is_integer(max_chars), do: max_chars

  defp submit_disabled?(form, upload, max_chars) do
    over_limit = remaining_chars(form, max_chars) < 0
    content_blank = String.trim(content_value(form)) == ""
    entries = upload_entries(upload)
    no_attachments = entries == []
    attachments_pending = Enum.any?(entries, &(!&1.done?))

    has_errors =
      match?(%Phoenix.LiveView.UploadConfig{}, upload) and
        (upload.errors != [] or Enum.any?(entries, &(!&1.valid?)))

    over_limit or (content_blank and no_attachments) or attachments_pending or has_errors
  end

  defp content_value(%Phoenix.HTML.Form{} = form) do
    (form.params || %{})
    |> Map.get("content", "")
    |> to_string()
  end

  defp content_value(_form), do: ""

  defp upload_entries(%Phoenix.LiveView.UploadConfig{} = upload), do: upload.entries
  defp upload_entries(_upload), do: []

  defp visibility_label(visibility) when is_binary(visibility) do
    case String.trim(visibility) do
      "public" -> "Public"
      "unlisted" -> "Unlisted"
      "private" -> "Private"
      "direct" -> "Direct"
      _ -> "Public"
    end
  end

  defp visibility_label(_visibility), do: "Public"

  defp language_label(language) when is_binary(language) do
    case String.trim(language) do
      "" -> "Auto"
      "auto" -> "Auto"
      value -> value
    end
  end

  defp language_label(_language), do: "Auto"

  defp upload_error_text(:too_large), do: "File is too large."
  defp upload_error_text(:not_accepted), do: "Unsupported file type."
  defp upload_error_text(:too_many_files), do: "Too many files selected."
  defp upload_error_text(_), do: "Upload failed."
end
