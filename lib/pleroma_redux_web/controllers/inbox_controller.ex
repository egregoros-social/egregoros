defmodule PleromaReduxWeb.InboxController do
  use PleromaReduxWeb, :controller

  alias PleromaRedux.Pipeline
  alias PleromaRedux.Users

  def inbox(conn, %{"nickname" => nickname}) do
    with %{} <- Users.get_by_nickname(nickname),
         activity when is_map(activity) <- conn.body_params,
         {:ok, _object} <- Pipeline.ingest(activity, local: false) do
      send_resp(conn, 202, "")
    else
      nil -> send_resp(conn, 404, "Not Found")
      _ -> send_resp(conn, 400, "Bad Request")
    end
  end
end
