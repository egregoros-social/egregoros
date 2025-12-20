defmodule PleromaReduxWeb.CoreComponentsTest do
  use PleromaReduxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PleromaReduxWeb.CoreComponents

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

  test "avatar renders an image when src is provided" do
    html =
      render_component(
        fn assigns -> apply(CoreComponents, :avatar, [assigns]) end,
        %{
          rest: %{},
          name: "Alice Example",
          src: "/uploads/avatar.png"
        }
      )

    assert html =~ ~s(data-role="avatar")
    assert html =~ ~s(<img)
    assert html =~ ~s(src="/uploads/avatar.png")
  end
end
