defmodule PleromaReduxWeb.FollowCollectionController do
  use PleromaReduxWeb, :controller

  alias PleromaRedux.Relationships
  alias PleromaRedux.Users

  def followers(conn, %{"nickname" => nickname}) do
    case Users.get_by_nickname(nickname) do
      nil ->
        send_resp(conn, 404, "Not found")

      user ->
        items =
          user.ap_id
          |> Relationships.list_follows_to()
          |> Enum.map(& &1.actor)

        respond_collection(conn, user.ap_id <> "/followers", items)
    end
  end

  def following(conn, %{"nickname" => nickname}) do
    case Users.get_by_nickname(nickname) do
      nil ->
        send_resp(conn, 404, "Not found")

      user ->
        items =
          user.ap_id
          |> Relationships.list_follows_by_actor()
          |> Enum.map(& &1.object)

        respond_collection(conn, user.ap_id <> "/following", items)
    end
  end

  defp respond_collection(conn, id, items) do
    payload = %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "id" => id,
      "type" => "OrderedCollection",
      "totalItems" => length(items),
      "orderedItems" => items
    }

    conn
    |> put_resp_content_type("application/activity+json")
    |> send_resp(200, Jason.encode!(payload))
  end
end
