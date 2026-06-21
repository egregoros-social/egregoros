defmodule EgregorosWeb.PleromaAPI.OffersController do
  use EgregorosWeb, :controller

  alias Egregoros.Activities.Accept
  alias Egregoros.Activities.Offer
  alias Egregoros.Activities.Reject
  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.User

  def accept(conn, %{"id" => id}) do
    current_user = conn.assigns.current_user

    with %User{} = current_user <- current_user,
         %Object{type: "Offer"} = offer_object <- fetch_offer(id),
         true <- offer_addressed_to_user?(offer_object, current_user),
         {:ok, _accept_object} <-
           Pipeline.ingest(Accept.build(current_user, offer_object), local: true) do
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

    with %User{} = current_user <- current_user,
         %Object{type: "Offer"} = offer_object <- fetch_offer(id),
         true <- offer_addressed_to_user?(offer_object, current_user),
         {:ok, _reject_object} <-
           Pipeline.ingest(Reject.build(current_user, offer_object), local: true) do
      json(conn, %{})
    else
      nil ->
        send_resp(conn, 404, "Not Found")

      _ ->
        send_resp(conn, 422, "Unprocessable Entity")
    end
  end

  defp fetch_offer(id) when is_binary(id) do
    id = String.trim(id)

    cond do
      id == "" ->
        nil

      true ->
        Objects.get(id) || Objects.get_by_ap_id(id)
    end
  end

  defp fetch_offer(_id), do: nil

  defp offer_addressed_to_user?(%Object{} = offer_object, %User{} = user) do
    user.ap_id in Offer.recipient_ap_ids(offer_object)
  end

  defp offer_addressed_to_user?(_offer_object, _user), do: false
end
