defmodule PleromaReduxWeb.PageControllerTest do
  use PleromaReduxWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Signal feed"
  end
end
