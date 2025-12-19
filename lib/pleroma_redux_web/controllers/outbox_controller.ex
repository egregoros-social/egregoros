defmodule PleromaReduxWeb.OutboxController do
  use PleromaReduxWeb, :controller

  alias PleromaRedux.Objects
  alias PleromaRedux.Users

  def outbox(conn, %{"nickname" => nickname}) do
    case Users.get_by_nickname(nickname) do
      nil ->
        send_resp(conn, 404, "Not Found")

      user ->
        items = Objects.list_notes_by_actor(user.ap_id)
        total = Objects.count_notes_by_actor(user.ap_id)

        json(conn, %{
          "@context" => "https://www.w3.org/ns/activitystreams",
          "id" => user.outbox,
          "type" => "OrderedCollection",
          "totalItems" => total,
          "orderedItems" => Enum.map(items, & &1.data)
        })
    end
  end
end
