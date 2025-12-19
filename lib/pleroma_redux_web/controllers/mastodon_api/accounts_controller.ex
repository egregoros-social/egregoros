defmodule PleromaReduxWeb.MastodonAPI.AccountsController do
  use PleromaReduxWeb, :controller

  alias PleromaRedux.Activities.Follow
  alias PleromaRedux.Activities.Undo
  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Relationships
  alias PleromaRedux.Users
  alias PleromaReduxWeb.MastodonAPI.AccountRenderer
  alias PleromaReduxWeb.MastodonAPI.RelationshipRenderer
  alias PleromaReduxWeb.MastodonAPI.StatusRenderer

  def verify_credentials(conn, _params) do
    json(conn, AccountRenderer.render_account(conn.assigns.current_user))
  end

  def show(conn, %{"id" => id}) do
    case Users.get(id) do
      nil -> send_resp(conn, 404, "Not Found")
      user -> json(conn, AccountRenderer.render_account(user))
    end
  end

  def statuses(conn, %{"id" => id}) do
    case Users.get(id) do
      nil ->
        send_resp(conn, 404, "Not Found")

      user ->
        objects = Objects.list_notes_by_actor(user.ap_id)
        json(conn, StatusRenderer.render_statuses(objects))
    end
  end

  def relationships(conn, params) do
    ids = Map.get(params, "id", [])

    relationships =
      ids
      |> List.wrap()
      |> Enum.map(&Users.get/1)
      |> Enum.filter(&is_map/1)
      |> Enum.map(&RelationshipRenderer.render_relationship(conn.assigns.current_user, &1))

    json(conn, relationships)
  end

  def follow(conn, %{"id" => id}) do
    with %{} = target <- Users.get(id),
         {:ok, _follow} <-
           Pipeline.ingest(Follow.build(conn.assigns.current_user, target),
             local: true
           ) do
      json(conn, RelationshipRenderer.render_relationship(conn.assigns.current_user, target))
    else
      nil -> send_resp(conn, 404, "Not Found")
      {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
    end
  end

  def unfollow(conn, %{"id" => id}) do
    with %{} = target <- Users.get(id),
         %{} =
           relationship <-
           Relationships.get_by_type_actor_object(
             "Follow",
             conn.assigns.current_user.ap_id,
             target.ap_id
           ),
         {:ok, _undo} <-
           Pipeline.ingest(Undo.build(conn.assigns.current_user, relationship.activity_ap_id),
             local: true
           ) do
      json(conn, RelationshipRenderer.render_relationship(conn.assigns.current_user, target))
    else
      nil -> send_resp(conn, 404, "Not Found")
      {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
    end
  end
end
