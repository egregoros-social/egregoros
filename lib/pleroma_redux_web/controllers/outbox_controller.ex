defmodule PleromaReduxWeb.OutboxController do
  use PleromaReduxWeb, :controller

  alias PleromaRedux.Objects
  alias PleromaRedux.Users

  def outbox(conn, %{"nickname" => nickname}) do
    case Users.get_by_nickname(nickname) do
      nil ->
        send_resp(conn, 404, "Not Found")

      user ->
        items = Objects.list_creates_by_actor(user.ap_id)
        total = Objects.count_creates_by_actor(user.ap_id)

        payload = %{
          "@context" => "https://www.w3.org/ns/activitystreams",
          "id" => user.outbox,
          "type" => "OrderedCollection",
          "totalItems" => total,
          "orderedItems" => Enum.map(items, & &1.data)
        }

        conn
        |> put_resp_content_type("application/activity+json")
        |> send_resp(200, Jason.encode!(payload))
    end
  end
end
