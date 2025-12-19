defmodule PleromaReduxWeb.MastodonAPI.NotificationsController do
  use PleromaReduxWeb, :controller

  def index(conn, _params) do
    json(conn, [])
  end
end
