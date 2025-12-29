defmodule EgregorosWeb.MastodonAPI.FollowRequestsController do
  use EgregorosWeb, :controller

  alias Egregoros.Activities.Accept
  alias Egregoros.Activities.Reject
  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Relationships
  alias Egregoros.Users
  alias EgregorosWeb.MastodonAPI.AccountRenderer

  @page_size 40

  def index(conn, _params) do
    current_user = conn.assigns.current_user

    accounts =
      "FollowRequest"
      |> Relationships.list_by_type_object(current_user.ap_id, @page_size)
      |> Enum.map(&Users.get_by_ap_id(&1.actor))
      |> Enum.filter(&is_map/1)
      |> Enum.map(&AccountRenderer.render_account/1)

    json(conn, accounts)
  end

  def authorize(conn, %{"id" => id}) do
    current_user = conn.assigns.current_user

    with %{} = requester <- Users.get(id),
         %{} = relationship <-
           Relationships.get_by_type_actor_object(
             "FollowRequest",
             requester.ap_id,
             current_user.ap_id
           ),
         follow_ap_id when is_binary(follow_ap_id) and follow_ap_id != "" <-
           relationship.activity_ap_id,
         %Object{type: "Follow"} = follow_object <- Objects.get_by_ap_id(follow_ap_id),
         {:ok, _accept_object} <-
           Pipeline.ingest(Accept.build(current_user, follow_object), local: true) do
      json(conn, %{})
    else
      nil ->
        send_resp(conn, 404, "Not Found")

      _ ->
        send_resp(conn, 422, "Unprocessable Entity")
    end
  end

  def reject(conn, %{"id" => id}) do
    current_user = conn.assigns.current_user

    with %{} = requester <- Users.get(id),
         %{} = relationship <-
           Relationships.get_by_type_actor_object(
             "FollowRequest",
             requester.ap_id,
             current_user.ap_id
           ),
         follow_ap_id when is_binary(follow_ap_id) and follow_ap_id != "" <-
           relationship.activity_ap_id,
         %Object{type: "Follow"} = follow_object <- Objects.get_by_ap_id(follow_ap_id),
         {:ok, _reject_object} <-
           Pipeline.ingest(Reject.build(current_user, follow_object), local: true) do
      json(conn, %{})
    else
      nil ->
        send_resp(conn, 404, "Not Found")

      _ ->
        send_resp(conn, 422, "Unprocessable Entity")
    end
  end
end
