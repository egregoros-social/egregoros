defmodule EgregorosWeb.AppShellTest do
  use EgregorosWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias EgregorosWeb.AppShell

  test "renders navigation links for signed-in users" do
    html =
      render_component(&AppShell.app_shell/1, %{
        id: "app-shell",
        nav_id: "app-nav",
        main_id: "app-main",
        aside_id: "app-aside",
        active: :timeline,
        current_user: %{nickname: "alice", name: "Alice Example"},
        notifications_count: 2,
        inner_block: [%{inner_block: fn _, _ -> "Main content" end}]
      })

    assert html =~ ~s(id="app-shell")
    assert html =~ ~s(id="app-nav")
    assert html =~ ~s(data-role="app-shell-search")
    assert html =~ ~s(data-role="nav-timeline")
    assert html =~ ~s(data-role="nav-search")
    assert html =~ ~s(data-role="nav-notifications")
    assert html =~ ~s(data-role="nav-badges")
    assert html =~ ~s(data-role="nav-messages")
    assert html =~ ~s(data-role="nav-profile")
    assert html =~ ~s(data-role="nav-notifications-count")
  end

  test "renders navigation links for signed-out users" do
    html =
      render_component(&AppShell.app_shell/1, %{
        id: "app-shell",
        nav_id: "app-nav",
        main_id: "app-main",
        aside_id: "app-aside",
        active: :timeline,
        current_user: nil,
        notifications_count: 0,
        inner_block: [%{inner_block: fn _, _ -> "Main content" end}]
      })

    assert html =~ ~s(data-role="app-shell-search")
    assert html =~ ~s(data-role="nav-timeline")
    assert html =~ ~s(data-role="nav-search")
    assert html =~ ~s(data-role="nav-login")
    assert html =~ ~s(data-role="nav-register")
  end

  test "marks active navigation links with aria-current" do
    html =
      render_component(&AppShell.app_shell/1, %{
        id: "app-shell",
        nav_id: "app-nav",
        main_id: "app-main",
        aside_id: "app-aside",
        active: :timeline,
        current_user: %{nickname: "alice", name: "Alice Example"},
        notifications_count: 2,
        inner_block: [%{inner_block: fn _, _ -> "Main content" end}]
      })

    assert html =~ ~r/<a[^>]*data-role="nav-timeline"[^>]*aria-current="page"/
    refute html =~ ~r/<a[^>]*data-role="nav-search"[^>]*aria-current="page"/
  end
end
