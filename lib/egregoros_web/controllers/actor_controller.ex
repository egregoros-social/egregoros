defmodule EgregorosWeb.ActorController do
  use EgregorosWeb, :controller

  alias Egregoros.E2EE
  alias Egregoros.Users
  alias EgregorosWeb.URL

  def show(conn, %{"nickname" => nickname}) do
    case Users.get_by_nickname(nickname) do
      nil ->
        send_resp(conn, 404, "Not found")

      user ->
        conn
        |> put_resp_content_type("application/activity+json")
        |> send_resp(200, Jason.encode!(actor_json(user)))
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
      "name" => user.name || user.nickname,
      "summary" => user.bio,
      "inbox" => user.inbox,
      "outbox" => user.outbox,
      "followers" => user.ap_id <> "/followers",
      "following" => user.ap_id <> "/following",
      "publicKey" => %{
        "id" => user.ap_id <> "#main-key",
        "owner" => user.ap_id,
        "publicKeyPem" => user.public_key
      }
    }
    |> maybe_put_icon(user)
    |> maybe_put_e2ee(user)
  end

  defp maybe_put_icon(actor, %{avatar_url: avatar_url})
       when is_binary(avatar_url) and avatar_url != "" do
    Map.put(actor, "icon", %{
      "type" => "Image",
      "url" => URL.absolute(avatar_url)
    })
  end

  defp maybe_put_icon(actor, _user), do: actor

  defp maybe_put_e2ee(actor, user) do
    keys = E2EE.public_keys_for_actor(user)

    if keys == [] do
      actor
    else
      actor
      |> Map.update!("@context", fn ctx ->
        ctx ++ [%{"egregoros" => URL.absolute("/schemas/egregoros#")}]
      end)
      |> Map.put("egregoros:e2ee", %{"version" => 1, "keys" => keys})
    end
  end
end
