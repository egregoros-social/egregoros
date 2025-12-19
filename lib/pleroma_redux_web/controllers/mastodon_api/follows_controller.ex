defmodule PleromaReduxWeb.MastodonAPI.FollowsController do
  use PleromaReduxWeb, :controller

  alias PleromaRedux.Federation
  alias PleromaReduxWeb.MastodonAPI.AccountRenderer

  def create(conn, %{"uri" => uri}) do
    uri = uri |> to_string() |> String.trim()

    if uri == "" do
      send_resp(conn, 422, "Unprocessable Entity")
    else
      case Federation.follow_remote(conn.assigns.current_user, uri) do
        {:ok, user} -> json(conn, AccountRenderer.render_account(user))
        {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
      end
    end
  end

  def create(conn, _params) do
    send_resp(conn, 422, "Unprocessable Entity")
  end
end

