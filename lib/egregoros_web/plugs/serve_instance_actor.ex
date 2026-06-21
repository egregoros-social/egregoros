defmodule EgregorosWeb.Plugs.ServeInstanceActor do
  import Plug.Conn

  alias Egregoros.Federation.InstanceActor
  alias Egregoros.VerifiableCredentials.DidWeb

  def init(opts), do: opts

  def call(%Plug.Conn{} = conn, _opts) do
    if conn.method == "GET" and conn.request_path == "/" and
         Phoenix.Controller.get_format(conn) == "json" do
      conn
      |> put_resp_header("vary", "accept")
      |> serve_actor()
      |> halt()
    else
      conn
    end
  end

  defp serve_actor(conn) do
    case InstanceActor.get_actor() do
      {:ok, actor} ->
        payload = actor_json(actor)

        conn
        |> put_resp_content_type("application/activity+json")
        |> send_resp(200, Jason.encode!(payload))

      {:error, _reason} ->
        send_resp(conn, 500, "Internal Server Error")
    end
  end

  defp actor_json(actor) do
    base_url = InstanceActor.ap_id()
    did = DidWeb.instance_did()

    %{
      "@context" => [
        "https://www.w3.org/ns/activitystreams",
        "https://w3id.org/security/v2",
        "https://w3id.org/security/data-integrity/v2"
      ],
      "id" => base_url,
      "type" => "Application",
      "preferredUsername" => actor.nickname,
      "name" => "Egregoros",
      "summary" => "Egregoros instance actor.",
      "inbox" => actor.inbox,
      "outbox" => actor.outbox,
      "followers" => base_url <> "/followers",
      "following" => base_url <> "/following",
      "publicKey" => %{
        "id" => base_url <> "#main-key",
        "owner" => base_url,
        "publicKeyPem" => actor.public_key
      }
    }
    |> maybe_put_also_known_as(did)
    |> maybe_put_assertion_method(actor)
  end

  defp maybe_put_assertion_method(actor, %{assertion_method: assertion_method})
       when is_list(assertion_method) or is_map(assertion_method) do
    Map.put(actor, "assertionMethod", assertion_method)
  end

  defp maybe_put_assertion_method(actor, _user), do: actor

  defp maybe_put_also_known_as(actor, did) when is_binary(did) and did != "" do
    Map.put(actor, "alsoKnownAs", [did])
  end

  defp maybe_put_also_known_as(actor, _did), do: actor
end
