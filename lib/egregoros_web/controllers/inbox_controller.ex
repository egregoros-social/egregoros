defmodule EgregorosWeb.InboxController do
  use EgregorosWeb, :controller

  plug EgregorosWeb.Plugs.RateLimitInbox
  plug EgregorosWeb.Plugs.VerifySignature

  alias Egregoros.Users
  alias Egregoros.Workers.IngestActivity

  def inbox(conn, %{"nickname" => nickname}) do
    with %{ap_id: inbox_user_ap_id} <- Users.get_by_nickname(nickname),
         activity when is_map(activity) <- conn.body_params,
         {:ok, _job} <-
           Oban.insert(
             IngestActivity.new(%{"activity" => activity, "inbox_user_ap_id" => inbox_user_ap_id})
           ) do
      send_resp(conn, 202, "")
    else
      nil -> send_resp(conn, 404, "Not Found")
      {:error, _changeset} -> send_resp(conn, 500, "Internal Server Error")
      _ -> send_resp(conn, 400, "Bad Request")
    end
  end
end
