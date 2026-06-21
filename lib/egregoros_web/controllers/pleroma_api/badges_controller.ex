defmodule EgregorosWeb.PleromaAPI.BadgesController do
  use EgregorosWeb, :controller

  alias Egregoros.Badges
  alias Egregoros.User

  def issue(conn, %{"badge_type" => badge_type, "recipient_ap_id" => recipient_ap_id}) do
    case conn.assigns.current_user do
      %User{admin: true} ->
        case Badges.issue_badge(badge_type, recipient_ap_id) do
          {:ok, %{offer: offer, credential: credential}} ->
            conn
            |> put_status(:created)
            |> json(%{
              "offer_id" => offer.ap_id,
              "credential_id" => credential.ap_id
            })

          _ ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{"error" => "unprocessable_entity"})
        end

      %User{} ->
        conn
        |> put_status(:forbidden)
        |> json(%{"error" => "forbidden"})

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{"error" => "unauthorized"})
    end
  end

  def issue(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{"error" => "unprocessable_entity"})
  end
end
