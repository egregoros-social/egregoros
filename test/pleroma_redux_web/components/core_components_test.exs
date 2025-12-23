defmodule PleromaReduxWeb.CoreComponentsTest do
  use PleromaReduxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PleromaReduxWeb.CoreComponents

  defp slot_text(text) when is_binary(text) do
    [%{inner_block: fn _, _ -> text end}]
  end

  test "button defaults to type button" do
    html =
      render_component(&CoreComponents.button/1, %{
        rest: %{},
        variant: nil,
        class: nil,
        inner_block: [%{inner_block: fn _, _ -> "Click" end}]
      })

    assert html =~ ~s(type="button")
  end

  test "button renders a link when navigation assigns are present" do
    html =
      render_component(&CoreComponents.button/1, %{
        rest: %{navigate: "/"},
        variant: "primary",
        size: "md",
        type: nil,
        class: nil,
        inner_block: slot_text("Go")
      })

    assert html =~ "<a"
    assert html =~ ~s(href="/")
    refute html =~ ~s(type="button")
  end

  test "button renders variant and size classes" do
    html =
      render_component(&CoreComponents.button/1, %{
        rest: %{},
        variant: "destructive",
        size: "sm",
        type: nil,
        class: nil,
        inner_block: slot_text("Delete")
      })

    assert html =~ "bg-red-600"
    assert html =~ "px-3 py-1.5 text-xs"
  end

  test "button advertises clickability with a pointer cursor" do
    html =
      render_component(&CoreComponents.button/1, %{
        rest: %{},
        variant: "primary",
        size: "md",
        type: nil,
        class: nil,
        inner_block: slot_text("Post")
      })

    assert html =~ "cursor-pointer"
  end

  test "card wraps content and exposes a stable data role" do
    html =
      render_component(
        fn assigns -> apply(CoreComponents, :card, [assigns]) end,
        %{
          rest: %{},
          inner_block: [%{inner_block: fn _, _ -> "Hello world" end}]
        }
      )

    assert html =~ "Hello world"
    assert html =~ ~s(data-role="card")
  end

  test "flash renders a message pulled from the flash map" do
    flash = %{"info" => "Welcome back"}

    html =
      render_component(&CoreComponents.flash/1, %{
        id: "flash-info",
        kind: :info,
        flash: flash,
        title: nil,
        class: nil,
        rest: %{},
        inner_block: []
      })

    assert html =~ ~s(id="flash-info")
    assert html =~ ~s(data-role="toast")
    assert html =~ "Welcome back"
  end

  test "flash prefers the inner block when provided" do
    flash = %{"info" => "Welcome back"}

    html =
      render_component(&CoreComponents.flash/1, %{
        id: "flash-info",
        kind: :info,
        flash: flash,
        title: "Greeting",
        class: nil,
        rest: %{},
        inner_block: slot_text("Custom message")
      })

    assert html =~ "Custom message"
    assert html =~ "Greeting"
    refute html =~ "Welcome back"
  end

  test "flash renders an error icon for error flashes" do
    flash = %{"error" => "Nope"}

    html =
      render_component(&CoreComponents.flash/1, %{
        id: "flash-error",
        kind: :error,
        flash: flash,
        title: nil,
        class: nil,
        rest: %{},
        inner_block: []
      })

    assert html =~ "hero-exclamation-circle"
    assert html =~ "Nope"
  end

  test "avatar falls back to an initial when no src is provided" do
    html =
      render_component(
        fn assigns -> apply(CoreComponents, :avatar, [assigns]) end,
        %{
          rest: %{},
          name: "Alice Example"
        }
      )

    assert html =~ ~s(data-role="avatar")
    assert html =~ ~r/>\s*A\s*</
  end

  test "avatar falls back to a question mark for empty names" do
    html =
      render_component(
        fn assigns -> apply(CoreComponents, :avatar, [assigns]) end,
        %{
          rest: %{},
          name: "   ",
          size: "xs"
        }
      )

    assert html =~ "h-7 w-7"
    assert html =~ ~r/>\s*\?\s*</
  end

  test "avatar renders an image when src is provided" do
    html =
      render_component(
        fn assigns -> apply(CoreComponents, :avatar, [assigns]) end,
        %{
          rest: %{},
          name: "Alice Example",
          src: "/uploads/avatar.png",
          alt: "Alice Example"
        }
      )

    assert html =~ ~s(data-role="avatar")
    assert html =~ ~s(<img)
    assert html =~ ~s(src="/uploads/avatar.png")
    assert html =~ ~s(alt="Alice Example")
  end

  test "time_ago does not render a timestamp for invalid values" do
    html =
      render_component(&CoreComponents.time_ago/1, %{
        at: nil,
        class: nil,
        data_role: "timestamp"
      })

    refute html =~ "<time"
  end

  test "time_ago renders a relative timestamp when given a DateTime" do
    html =
      render_component(&CoreComponents.time_ago/1, %{
        at: DateTime.utc_now(),
        class: nil,
        data_role: "timestamp"
      })

    assert html =~ "<time"
    assert html =~ "datetime="
    assert html =~ ~r/>\s*now\s*</
  end

  test "input renders hidden fields" do
    html =
      render_component(&CoreComponents.input/1, %{
        type: "hidden",
        id: "token",
        name: "token",
        value: "secret",
        rest: %{}
      })

    assert html =~ ~s(type="hidden")
    assert html =~ ~s(value="secret")
  end

  test "input renders checkbox fields with errors" do
    html =
      render_component(&CoreComponents.input/1, %{
        type: "checkbox",
        id: "accept",
        name: "accept",
        value: true,
        label: "Accept",
        errors: ["must be accepted"],
        class: nil,
        error_class: nil,
        rest: %{}
      })

    assert html =~ ~s(type="checkbox")
    assert html =~ "must be accepted"
  end

  test "input renders select fields with a prompt" do
    html =
      render_component(&CoreComponents.input/1, %{
        type: "select",
        id: "role",
        name: "role",
        value: "user",
        label: "Role",
        prompt: "Pick one",
        options: [Admin: "admin", User: "user"],
        multiple: false,
        errors: [],
        class: nil,
        error_class: nil,
        rest: %{}
      })

    assert html =~ "<select"
    assert html =~ ~s(Pick one)
    assert html =~ ~s(value="user")
  end

  test "input renders textarea fields" do
    html =
      render_component(&CoreComponents.input/1, %{
        type: "textarea",
        id: "bio",
        name: "bio",
        value: "hello",
        label: "Bio",
        errors: [],
        class: nil,
        error_class: nil,
        rest: %{}
      })

    assert html =~ "<textarea"
    assert html =~ "hello"
  end

  test "table supports plain lists and live streams" do
    rows = [%{id: 1, name: "Alice"}]

    html =
      render_component(&CoreComponents.table/1, %{
        id: "users-table",
        rows: rows,
        row_id: nil,
        row_click: nil,
        row_item: &Function.identity/1,
        col: [
          %{label: "Name", inner_block: fn _, row -> row.name end}
        ],
        action: [
          %{inner_block: fn _, _row -> "Action" end}
        ]
      })

    assert html =~ "users-table"
    assert html =~ "Name"
    assert html =~ "Alice"
    assert html =~ "Action"

    stream =
      Phoenix.LiveView.LiveStream.new(:users, "ref", rows, [])
      |> Phoenix.LiveView.LiveStream.mark_consumable()

    stream_html =
      render_component(&CoreComponents.table/1, %{
        id: "users-stream-table",
        rows: stream,
        row_id: nil,
        row_click: nil,
        row_item: fn {_id, row} -> row end,
        col: [
          %{label: "Name", inner_block: fn _, row -> row.name end}
        ],
        action: []
      })

    assert stream_html =~ "users-stream-table"
    assert stream_html =~ "Alice"
  end

  test "list renders its labeled items" do
    html =
      render_component(&CoreComponents.list/1, %{
        item: [
          %{title: "Title", inner_block: fn _, _ -> "Value" end}
        ]
      })

    assert html =~ "Title"
    assert html =~ "Value"
  end

  test "icon renders heroicons as span class names" do
    html =
      render_component(&CoreComponents.icon/1, %{
        name: "hero-x-mark",
        class: "size-7"
      })

    assert html =~ ~s(class="hero-x-mark size-7")
  end

  test "translates errors with and without counts" do
    assert CoreComponents.translate_error({"should be at least %{count} character(s)", count: 2}) =~
             "2"

    assert CoreComponents.translate_error({"can't be blank", []}) =~ "can't be blank"

    errors = [email: {"can't be blank", []}, name: {"is invalid", []}]
    assert CoreComponents.translate_errors(errors, :email) == ["can't be blank"]
  end
end
