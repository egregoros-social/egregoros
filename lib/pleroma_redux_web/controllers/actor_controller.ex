defmodule PleromaReduxWeb.ActorController do
  use PleromaReduxWeb, :controller

  alias PleromaRedux.Users

  def show(conn, %{"nickname" => nickname}) do
    case Users.get_by_nickname(nickname) do
      nil ->
        send_resp(conn, 404, "Not found")

      user ->
        conn
        |> put_resp_content_type("application/activity+json")
        |> json(actor_json(user))
    end
  end

  defp actor_json(user) do
    %{
      "@context" => [
        "https://www.w3.org/ns/activitystreams",
        "https://w3id.org/security/v1"
      ],
      "id" => user.ap_id,
      "type" => "Person",
      "preferredUsername" => user.nickname,
      "inbox" => user.inbox,
      "outbox" => user.outbox,
      "publicKey" => %{
        "id" => user.ap_id <> "#main-key",
        "owner" => user.ap_id,
        "publicKeyPem" => user.public_key
      }
    }
  end
end
