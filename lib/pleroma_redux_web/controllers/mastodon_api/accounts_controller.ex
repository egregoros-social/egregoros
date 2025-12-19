defmodule PleromaReduxWeb.MastodonAPI.AccountsController do
  use PleromaReduxWeb, :controller

  alias PleromaRedux.Users
  alias PleromaReduxWeb.MastodonAPI.AccountRenderer

  def verify_credentials(conn, _params) do
    json(conn, AccountRenderer.render_account(conn.assigns.current_user))
  end

  def show(conn, %{"id" => id}) do
    case Users.get(id) do
      nil -> send_resp(conn, 404, "Not Found")
      user -> json(conn, AccountRenderer.render_account(user))
    end
  end
end
