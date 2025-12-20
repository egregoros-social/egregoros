defmodule PleromaReduxWeb.CoreComponents do
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
  use Gettext, backend: PleromaReduxWeb.Gettext

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
        "pointer-events-auto w-full max-w-sm animate-rise overflow-hidden rounded-2xl border px-4 py-3 shadow-lg shadow-slate-900/10 backdrop-blur",
        "border-white/70 bg-white/90 text-slate-900 dark:border-slate-700/70 dark:bg-slate-950/70 dark:text-slate-100",
        @kind == :info && "ring-1 ring-slate-900/5 dark:ring-white/10",
        @kind == :error &&
          "border-rose-200/70 ring-1 ring-rose-200/70 dark:border-rose-500/30 dark:ring-rose-500/20",
        @class
      ]}
      {@rest}
    >
      <div class="flex items-start gap-3">
        <div class="mt-0.5 shrink-0">
          <.icon
            :if={@kind == :info}
            name="hero-information-circle"
            class="size-5 text-slate-500 dark:text-slate-300"
          />
          <.icon
            :if={@kind == :error}
            name="hero-exclamation-circle"
            class="size-5 text-rose-600 dark:text-rose-400"
          />
        </div>

        <div class="min-w-0 flex-1">
          <p :if={@title} class="font-semibold leading-6">{@title}</p>
          <p class="text-sm leading-6 text-slate-700 dark:text-slate-200">{msg}</p>
        </div>

        <button
          type="button"
          class="group -m-1 inline-flex items-center justify-center rounded-xl p-1 text-slate-500 transition hover:bg-slate-900/5 hover:text-slate-900 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 dark:text-slate-300 dark:hover:bg-white/10 dark:hover:text-white"
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
    include: ~w(href navigate patch method download phx-click phx-disable-with phx-target)

  attr :class, :any, default: nil
  attr :type, :string, default: nil
  attr :variant, :string, values: ~w(primary secondary ghost destructive), default: "primary"
  attr :size, :string, values: ~w(sm md lg), default: "md"
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    link? = rest[:href] || rest[:navigate] || rest[:patch]

    base_classes = [
      "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-full font-semibold transition",
      "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 focus-visible:ring-offset-2 focus-visible:ring-offset-white",
      "disabled:pointer-events-none disabled:opacity-50 dark:focus-visible:ring-offset-slate-950"
    ]

    size_classes =
      case assigns.size do
        "sm" -> "px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em]"
        "lg" -> "px-6 py-3 text-base"
        _ -> "px-5 py-3 text-sm"
      end

    variant_classes =
      case assigns.variant do
        "secondary" ->
          "border border-slate-200/80 bg-white/70 text-slate-700 shadow-sm shadow-slate-200/20 hover:-translate-y-0.5 hover:bg-white dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-200 dark:shadow-slate-900/40 dark:hover:bg-slate-950"

        "ghost" ->
          "bg-transparent text-slate-700 hover:bg-slate-900/5 dark:text-slate-200 dark:hover:bg-white/10"

        "destructive" ->
          "bg-rose-600 text-white shadow-lg shadow-rose-600/20 hover:-translate-y-0.5 hover:bg-rose-500 dark:bg-rose-500 dark:hover:bg-rose-400"

        _ ->
          "bg-slate-900 text-white shadow-lg shadow-slate-900/20 hover:-translate-y-0.5 hover:bg-slate-800 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-white"
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
        "rounded-3xl border border-white/80 bg-white/80 shadow-xl shadow-slate-200/40 backdrop-blur",
        "dark:border-slate-700/60 dark:bg-slate-900/70 dark:shadow-slate-900/40",
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
        "xs" -> {"h-7 w-7 rounded-lg", "text-xs"}
        "sm" -> {"h-9 w-9 rounded-xl", "text-sm"}
        "lg" -> {"h-14 w-14 rounded-2xl", "text-base"}
        "xl" -> {"h-16 w-16 rounded-2xl", "text-lg"}
        _ -> {"h-11 w-11 rounded-2xl", "text-sm"}
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
        "inline-flex shrink-0 items-center justify-center overflow-hidden border border-slate-200/80 bg-white shadow-sm shadow-slate-200/30",
        "dark:border-slate-700/60 dark:bg-slate-950/60 dark:shadow-slate-900/40",
        @box_classes,
        @class
      ]}
      {@rest}
    >
      <%= if is_binary(@src) and @src != "" do %>
        <img src={@src} alt={@alt} class="h-full w-full object-cover" loading="lazy" />
      <% else %>
        <span class={["font-semibold text-slate-700 dark:text-slate-200", @text_classes]}>
          {@initial}
        </span>
      <% end %>
    </span>
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
              "h-4 w-4 rounded border-slate-300 text-slate-900 shadow-sm focus:ring-2 focus:ring-slate-300 dark:border-slate-600 dark:bg-slate-950 dark:text-slate-100 dark:focus:ring-slate-600",
            @errors != [] && (@error_class || "border-rose-400 dark:border-rose-500/50")
          ]}
          {@rest}
        />
        <span :if={@label} class="select-none">{@label}</span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="space-y-1">
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
            "w-full rounded-2xl border border-slate-200/80 bg-white/70 px-4 py-3 text-sm text-slate-900 outline-none transition focus:border-slate-400 focus:ring-2 focus:ring-slate-200 dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-100 dark:focus:border-slate-400 dark:focus:ring-slate-600",
          @errors != [] && (@error_class || "border-rose-400 dark:border-rose-500/50")
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
    <div class="space-y-1">
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
            "w-full resize-none rounded-2xl border border-slate-200/80 bg-white/70 px-4 py-3 text-sm text-slate-900 outline-none transition focus:border-slate-400 focus:ring-2 focus:ring-slate-200 dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-100 dark:focus:border-slate-400 dark:focus:ring-slate-600",
          @errors != [] && (@error_class || "border-rose-400 dark:border-rose-500/50")
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
    <div class="space-y-1">
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
            "w-full rounded-2xl border border-slate-200/80 bg-white/70 px-4 py-3 text-sm text-slate-900 outline-none transition focus:border-slate-400 focus:ring-2 focus:ring-slate-200 dark:border-slate-700/80 dark:bg-slate-950/60 dark:text-slate-100 dark:focus:border-slate-400 dark:focus:ring-slate-600",
          @errors != [] && (@error_class || "border-rose-400 dark:border-rose-500/50")
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
    <p class="mt-1.5 flex items-center gap-2 text-sm text-rose-600 dark:text-rose-400">
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
        <h1 class="text-lg font-semibold leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-slate-600 dark:text-slate-300">
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
    <div class="overflow-x-auto rounded-2xl border border-slate-200/80 bg-white/70 shadow-sm shadow-slate-200/20 dark:border-slate-700/70 dark:bg-slate-950/60 dark:shadow-slate-900/40">
      <table class="min-w-full divide-y divide-slate-200/80 text-sm dark:divide-slate-700/70">
        <thead class="bg-slate-50/80 dark:bg-slate-900/60">
          <tr>
            <th
              :for={col <- @col}
              scope="col"
              class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-[0.2em] text-slate-600 dark:text-slate-300"
            >
              {col[:label]}
            </th>
            <th
              :if={@action != []}
              scope="col"
              class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-[0.2em] text-slate-600 dark:text-slate-300"
            >
              <span class="sr-only">{gettext("Actions")}</span>
            </th>
          </tr>
        </thead>
        <tbody
          id={@id}
          phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}
          class="divide-y divide-slate-200/70 dark:divide-slate-700/70"
        >
          <tr
            :for={row <- @rows}
            id={@row_id && @row_id.(row)}
            class="transition hover:bg-slate-900/5 dark:hover:bg-white/5"
          >
            <td
              :for={col <- @col}
              phx-click={@row_click && @row_click.(row)}
              class={["px-4 py-3 align-top", @row_click && "cursor-pointer"]}
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
    <dl class="divide-y divide-slate-200/70 rounded-2xl border border-slate-200/80 bg-white/70 text-sm shadow-sm shadow-slate-200/20 dark:divide-slate-700/70 dark:border-slate-700/70 dark:bg-slate-950/60 dark:shadow-slate-900/40">
      <div
        :for={item <- @item}
        class="flex flex-col gap-1 px-4 py-3 sm:flex-row sm:items-start sm:justify-between"
      >
        <dt class="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500 dark:text-slate-400">
          {item.title}
        </dt>
        <dd class="text-slate-800 dark:text-slate-200">{render_slot(item)}</dd>
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
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
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
      Gettext.dngettext(PleromaReduxWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(PleromaReduxWeb.Gettext, "errors", msg, opts)
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
