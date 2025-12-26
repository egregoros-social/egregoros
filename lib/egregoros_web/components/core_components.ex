defmodule EgregorosWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework.
  The components in this module form a small, app-specific design system so
  templates can stay consistent without repeating large class lists.

  """
  use Phoenix.Component
  use Gettext, backend: EgregorosWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :class, :any, default: nil, doc: "additional classes for the flash container"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      data-role="toast"
      class={[
        "pointer-events-auto w-full max-w-sm motion-safe:animate-rise overflow-hidden rounded-xl border px-4 py-3 shadow-lg",
        @kind == :info &&
          "border-slate-200 bg-white text-slate-900 dark:border-slate-700 dark:bg-slate-800 dark:text-white",
        @kind == :error &&
          "border-red-200 bg-red-50 text-red-900 dark:border-red-800 dark:bg-red-900/50 dark:text-red-100",
        @class
      ]}
      {@rest}
    >
      <div class="flex items-start gap-3">
        <div class="mt-0.5 shrink-0">
          <.icon
            :if={@kind == :info}
            name="hero-information-circle"
            class="size-5 text-violet-600 dark:text-violet-400"
          />
          <.icon
            :if={@kind == :error}
            name="hero-exclamation-circle"
            class="size-5 text-red-600 dark:text-red-400"
          />
        </div>

        <div class="min-w-0 flex-1">
          <p :if={@title} class="font-semibold leading-6">{@title}</p>
          <p class="text-sm leading-6 text-slate-600 dark:text-slate-300">{msg}</p>
        </div>

        <button
          type="button"
          class="group -m-1 inline-flex items-center justify-center rounded-lg p-1 text-slate-400 transition hover:bg-slate-100 hover:text-slate-600 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-500 dark:text-slate-500 dark:hover:bg-slate-700 dark:hover:text-slate-300"
          aria-label={gettext("close")}
        >
          <.icon name="hero-x-mark" class="size-4 opacity-70 group-hover:opacity-100" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global,
    include:
      ~w(href navigate patch method download disabled phx-click phx-disable-with phx-target)

  attr :class, :any, default: nil
  attr :type, :string, default: nil
  attr :variant, :string, values: ~w(primary secondary ghost destructive), default: "primary"
  attr :size, :string, values: ~w(sm md lg), default: "md"
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    link? = rest[:href] || rest[:navigate] || rest[:patch]

    base_classes = [
      "inline-flex cursor-pointer items-center justify-center gap-2 whitespace-nowrap rounded-lg font-semibold transition-all",
      "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-500 focus-visible:ring-offset-2",
      "disabled:pointer-events-none disabled:opacity-50 dark:focus-visible:ring-offset-slate-900"
    ]

    size_classes =
      case assigns.size do
        "sm" -> "px-3 py-1.5 text-xs"
        "lg" -> "px-6 py-3 text-base"
        _ -> "px-4 py-2 text-sm"
      end

    variant_classes =
      case assigns.variant do
        "secondary" ->
          "border border-slate-200 bg-white text-slate-700 shadow-sm hover:bg-slate-50 hover:text-slate-900 dark:border-slate-700 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700 dark:hover:text-white"

        "ghost" ->
          "bg-transparent text-slate-600 hover:bg-slate-100 hover:text-slate-900 dark:text-slate-300 dark:hover:bg-slate-800 dark:hover:text-white"

        "destructive" ->
          "bg-red-600 text-white shadow-sm hover:bg-red-500 dark:bg-red-600 dark:hover:bg-red-500"

        _ ->
          "bg-violet-600 text-white shadow-sm hover:bg-violet-500 dark:bg-violet-600 dark:hover:bg-violet-500"
      end

    assigns =
      assigns
      |> assign(:button_type, if(link?, do: nil, else: assigns.type || "button"))
      |> assign(:button_class, [base_classes, size_classes, variant_classes, assigns.class])

    if link? do
      ~H"""
      <.link class={@button_class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button type={@button_type} class={@button_class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an emoji picker for composer-like forms.

  This component is purely client-side via the `EmojiPicker` LiveView hook.
  """
  attr :emojis, :list,
    default: ["😀", "😍", "🔥", "👍", "❤️", "🎉", "😮", "😢"],
    doc: "emoji options to render"

  attr :id, :string, default: nil, doc: "optional DOM id"
  attr :class, :any, default: nil, doc: "additional classes for the picker wrapper"

  def compose_emoji_picker(assigns) do
    ~H"""
    <div
      id={@id}
      class={["relative", @class]}
      data-role="compose-emoji-picker"
      phx-hook="EmojiPicker"
    >
      <button
        type="button"
        data-role="compose-emoji"
        aria-label="Emoji picker"
        aria-expanded="false"
        class="inline-flex h-10 w-10 items-center justify-center rounded-lg text-slate-500 transition hover:bg-slate-100 hover:text-slate-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-500 dark:text-slate-400 dark:hover:bg-slate-700 dark:hover:text-slate-200"
      >
        <.icon name="hero-face-smile" class="size-5" />
      </button>

      <div
        data-role="compose-emoji-menu"
        data-state="closed"
        class={[
          "absolute left-0 top-full z-30 mt-2 hidden w-64 rounded-xl border border-slate-200 bg-white p-4 shadow-xl dark:border-slate-700 dark:bg-slate-800",
          "focus-within:ring-2 focus-within:ring-violet-500"
        ]}
      >
        <p class="text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-slate-400">
          Emoji
        </p>

        <div class="mt-3 grid grid-cols-8 gap-1">
          <button
            :for={emoji <- @emojis}
            type="button"
            data-role="compose-emoji-option"
            data-emoji={emoji}
            class="inline-flex h-9 w-9 items-center justify-center rounded-lg text-xl transition hover:bg-slate-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-500 dark:hover:bg-slate-700"
          >
            {emoji}
          </button>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a surface container (card/panel) with consistent styling.
  """
  attr :rest, :global
  attr :class, :any, default: nil
  attr :data_role, :string, default: "card"
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <section
      data-role={@data_role}
      class={[
        "rounded-xl border border-slate-200 bg-white shadow-sm",
        "dark:border-slate-700 dark:bg-slate-800/50",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc """
  Renders an actor/avatar image with a graceful initial fallback.
  """
  attr :rest, :global
  attr :class, :any, default: nil
  attr :data_role, :string, default: "avatar"
  attr :name, :string, required: true
  attr :src, :string, default: nil
  attr :alt, :string, default: nil
  attr :size, :string, values: ~w(xs sm md lg xl), default: "md"

  def avatar(assigns) do
    assigns = assign_new(assigns, :alt, fn -> assigns.name end)

    {box_classes, text_classes} =
      case assigns.size do
        "xs" -> {"h-7 w-7 rounded-md", "text-xs"}
        "sm" -> {"h-9 w-9 rounded-lg", "text-sm"}
        "lg" -> {"h-14 w-14 rounded-xl", "text-base"}
        "xl" -> {"h-16 w-16 rounded-xl", "text-lg"}
        _ -> {"h-11 w-11 rounded-xl", "text-sm"}
      end

    assigns =
      assigns
      |> assign(:box_classes, box_classes)
      |> assign(:text_classes, text_classes)
      |> assign(:initial, avatar_initial(assigns.name))

    ~H"""
    <span
      data-role={@data_role}
      class={[
        "inline-flex shrink-0 items-center justify-center overflow-hidden border-2 border-slate-200 bg-slate-100",
        "dark:border-slate-600 dark:bg-slate-700",
        @box_classes,
        @class
      ]}
      {@rest}
    >
      <%= if is_binary(@src) and @src != "" do %>
        <img src={@src} alt={@alt} class="h-full w-full object-cover" loading="lazy" />
      <% else %>
        <span class={["font-bold text-slate-600 dark:text-slate-300", @text_classes]}>
          {@initial}
        </span>
      <% end %>
    </span>
    """
  end

  @doc false
  def upload_entry_kind(%{client_type: type}) when is_binary(type) do
    cond do
      String.starts_with?(type, "image/") -> :image
      String.starts_with?(type, "video/") -> :video
      String.starts_with?(type, "audio/") -> :audio
      true -> :other
    end
  end

  def upload_entry_kind(_entry), do: :other

  @doc false
  def upload_entry_icon(entry) do
    case upload_entry_kind(entry) do
      :video -> "hero-film"
      :audio -> "hero-musical-note"
      _ -> "hero-paper-clip"
    end
  end

  @doc false
  def upload_entry_description_placeholder(entry) do
    case upload_entry_kind(entry) do
      :image -> "Describe the image for screen readers"
      :video -> "Describe the video for screen readers"
      :audio -> "Describe the audio for screen readers"
      _ -> "Describe the attachment for screen readers"
    end
  end

  @doc """
  Renders a compact preview for an uploaded media entry.

  Designed for small thumbnail containers. Supports:
  - image previews (via built-in LiveView preview hook)
  - video thumbnails (first frame)
  - icons for audio/other files
  """
  attr :entry, :any, required: true
  attr :class, :any, default: nil
  attr :data_role, :string, default: "upload-preview"

  def upload_entry_preview(assigns) do
    assigns = assign(assigns, :kind, upload_entry_kind(assigns.entry))

    ~H"""
    <%= case @kind do %>
      <% :image -> %>
        <.live_img_preview
          entry={@entry}
          data-role={@data_role}
          data-kind="image"
          class={["h-full w-full object-cover", @class]}
        />
      <% :video -> %>
        <video
          id={"phx-preview-thumb-#{@entry.ref}"}
          data-phx-upload-ref={@entry.upload_ref}
          data-phx-entry-ref={@entry.ref}
          data-phx-hook="Phoenix.LiveImgPreview"
          data-phx-update="ignore"
          phx-no-format
          data-role={@data_role}
          data-kind="video"
          class={["h-full w-full bg-black object-cover", @class]}
          muted
          playsinline
          preload="metadata"
        >
        </video>

        <div class="pointer-events-none absolute inset-0 flex items-center justify-center">
          <span class="inline-flex h-8 w-8 items-center justify-center rounded-full bg-black/50 text-white">
            <.icon name="hero-play" class="size-4" />
          </span>
        </div>
      <% _ -> %>
        <div
          data-role={@data_role}
          data-kind={to_string(@kind)}
          class="flex h-full w-full items-center justify-center bg-slate-100 text-slate-500 dark:bg-slate-800 dark:text-slate-400"
        >
          <.icon name={upload_entry_icon(@entry)} class="size-7" />
        </div>
    <% end %>
    """
  end

  @doc """
  Renders a full-width inline player for uploaded audio/video entries.

  Uses LiveView's built-in preview hook to set `src` on the element.
  """
  attr :entry, :any, required: true
  attr :class, :any, default: nil
  attr :data_role, :string, default: "upload-player"

  def upload_entry_player(assigns) do
    assigns = assign(assigns, :kind, upload_entry_kind(assigns.entry))

    ~H"""
    <%= case @kind do %>
      <% :video -> %>
        <video
          id={"phx-preview-player-#{@entry.ref}"}
          data-phx-upload-ref={@entry.upload_ref}
          data-phx-entry-ref={@entry.ref}
          data-phx-hook="Phoenix.LiveImgPreview"
          data-phx-update="ignore"
          phx-no-format
          data-role={@data_role}
          data-kind="video"
          class={["w-full rounded-lg bg-black shadow-sm", @class]}
          controls
          preload="metadata"
          playsinline
        >
        </video>
      <% :audio -> %>
        <audio
          id={"phx-preview-player-#{@entry.ref}"}
          data-phx-upload-ref={@entry.upload_ref}
          data-phx-entry-ref={@entry.ref}
          data-phx-hook="Phoenix.LiveImgPreview"
          data-phx-update="ignore"
          phx-no-format
          data-role={@data_role}
          data-kind="audio"
          class={["w-full", @class]}
          controls
          preload="metadata"
        >
        </audio>
      <% _ -> %>
    <% end %>
    """
  end

  @doc """
  Renders a human-friendly relative timestamp.
  """
  attr :at, :any, required: true
  attr :class, :any, default: nil
  attr :data_role, :string, default: "timestamp"

  def time_ago(assigns) do
    assigns =
      assigns
      |> assign(:iso, EgregorosWeb.Time.iso8601(assigns.at))
      |> assign(:label, EgregorosWeb.Time.relative(assigns.at))

    ~H"""
    <time
      :if={is_binary(@iso) and @iso != "" and is_binary(@label) and @label != ""}
      data-role={@data_role}
      datetime={@iso}
      title={@iso}
      class={["text-xs font-medium text-slate-500 dark:text-slate-400", @class]}
    >
      {@label}
    </time>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://hexdocs.pm/phoenix_html/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="space-y-1">
      <label class="inline-flex items-center gap-3 text-sm text-slate-700 dark:text-slate-200">
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={[
            @class ||
              "h-4 w-4 rounded border-slate-300 text-violet-600 shadow-sm focus:ring-2 focus:ring-violet-500 dark:border-slate-600 dark:bg-slate-800 dark:focus:ring-violet-400",
            @errors != [] && (@error_class || "border-red-400 dark:border-red-500")
          ]}
          {@rest}
        />
        <span :if={@label} class="select-none font-medium">{@label}</span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="space-y-1.5">
      <label
        :if={@label}
        for={@id}
        class="block text-sm font-semibold text-slate-700 dark:text-slate-200"
      >
        {@label}
      </label>
      <select
        id={@id}
        name={@name}
        class={[
          @class ||
            "w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900 outline-none transition focus:border-violet-500 focus:ring-2 focus:ring-violet-500/20 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100 dark:focus:border-violet-400",
          @errors != [] && (@error_class || "border-red-400 dark:border-red-500")
        ]}
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="space-y-1.5">
      <label
        :if={@label}
        for={@id}
        class="block text-sm font-semibold text-slate-700 dark:text-slate-200"
      >
        {@label}
      </label>
      <textarea
        id={@id}
        name={@name}
        class={[
          @class ||
            "w-full resize-none rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900 outline-none transition focus:border-violet-500 focus:ring-2 focus:ring-violet-500/20 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100 dark:focus:border-violet-400",
          @errors != [] && (@error_class || "border-red-400 dark:border-red-500")
        ]}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="space-y-1.5">
      <label
        :if={@label}
        for={@id}
        class="block text-sm font-semibold text-slate-700 dark:text-slate-200"
      >
        {@label}
      </label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          @class ||
            "w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900 outline-none transition focus:border-violet-500 focus:ring-2 focus:ring-violet-500/20 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100 dark:focus:border-violet-400",
          @errors != [] && (@error_class || "border-red-400 dark:border-red-500")
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1 flex items-center gap-2 text-sm font-medium text-red-600 dark:text-red-400">
      <.icon name="hero-exclamation-circle" class="size-4" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-bold text-slate-900 dark:text-white">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="mt-1 text-sm text-slate-600 dark:text-slate-400">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="overflow-x-auto rounded-xl border border-slate-200 bg-white shadow-sm dark:border-slate-700 dark:bg-slate-800/50">
      <table class="min-w-full divide-y divide-slate-200 text-sm dark:divide-slate-700">
        <thead class="bg-slate-50 dark:bg-slate-800">
          <tr>
            <th
              :for={col <- @col}
              scope="col"
              class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-slate-600 dark:text-slate-400"
            >
              {col[:label]}
            </th>
            <th
              :if={@action != []}
              scope="col"
              class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-slate-600 dark:text-slate-400"
            >
              <span class="sr-only">{gettext("Actions")}</span>
            </th>
          </tr>
        </thead>
        <tbody
          id={@id}
          phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}
          class="divide-y divide-slate-200 dark:divide-slate-700"
        >
          <tr
            :for={row <- @rows}
            id={@row_id && @row_id.(row)}
            class="transition hover:bg-slate-50 dark:hover:bg-slate-700/50"
          >
            <td
              :for={col <- @col}
              phx-click={@row_click && @row_click.(row)}
              class={[
                "px-4 py-3 align-top text-slate-900 dark:text-slate-100",
                @row_click && "cursor-pointer"
              ]}
            >
              {render_slot(col, @row_item.(row))}
            </td>
            <td :if={@action != []} class="px-4 py-3 text-right align-top">
              <div class="inline-flex items-center justify-end gap-3">
                <%= for action <- @action do %>
                  {render_slot(action, @row_item.(row))}
                <% end %>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <dl class="divide-y divide-slate-200 rounded-xl border border-slate-200 bg-white text-sm shadow-sm dark:divide-slate-700 dark:border-slate-700 dark:bg-slate-800/50">
      <div
        :for={item <- @item}
        class="flex flex-col gap-1 px-4 py-3 sm:flex-row sm:items-start sm:justify-between"
      >
        <dt class="text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-slate-400">
          {item.title}
        </dt>
        <dd class="font-medium text-slate-900 dark:text-slate-100">{render_slot(item)}</dd>
      </div>
    </dl>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-out duration-200", "opacity-0 translate-y-2",
         "opacity-100 translate-y-0"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 150,
      transition:
        {"transition-all ease-in duration-150", "opacity-100 translate-y-0",
         "opacity-0 translate-y-2"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(EgregorosWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(EgregorosWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  defp avatar_initial(name) when is_binary(name) do
    name
    |> String.trim()
    |> case do
      "" -> "?"
      trimmed -> trimmed |> String.first() |> String.upcase()
    end
  end

  defp avatar_initial(_name), do: "?"
end
