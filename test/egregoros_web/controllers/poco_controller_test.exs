defmodule EgregorosWeb.PocoControllerTest do
  use EgregorosWeb.ConnCase, async: true

  test "GET /poco returns an empty Portable Contacts response", %{conn: conn} do
    assert conn |> get("/poco") |> json_response(200) == %{"entry" => []}
  end
end

