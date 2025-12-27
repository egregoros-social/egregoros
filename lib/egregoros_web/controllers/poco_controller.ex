defmodule EgregorosWeb.PocoController do
  use EgregorosWeb, :controller

  def index(conn, _params) do
    json(conn, %{"entry" => []})
  end
end

