defmodule EgregorosWeb.WebSockTest do
  use EgregorosWeb.ConnCase, async: true

  test "upgrade/3 delegates to the configured implementation with default opts", %{conn: conn} do
    expect(EgregorosWeb.WebSock.Mock, :upgrade, fn passed_conn, handler, state, opts ->
      assert passed_conn == conn
      assert handler == EgregorosWeb.WebSock.Stub
      assert state == :connected
      assert opts == []

      passed_conn
    end)

    assert %Plug.Conn{} =
             EgregorosWeb.WebSock.upgrade(conn, EgregorosWeb.WebSock.Stub, :connected)
  end
end
