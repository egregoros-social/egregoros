defmodule EgregorosWeb.DidController do
  use EgregorosWeb, :controller

  alias Egregoros.Federation.InstanceActor
  alias Egregoros.VerifiableCredentials.DidWeb

  def show(conn, _params) do
    case InstanceActor.get_actor() do
      {:ok, actor} ->
        case DidWeb.instance_document(actor) do
          {:ok, document} ->
            conn
            |> put_resp_content_type("application/did+ld+json")
            |> send_resp(200, Jason.encode!(document))

          _ ->
            send_resp(conn, 500, "Internal Server Error")
        end

      _ ->
        send_resp(conn, 500, "Internal Server Error")
    end
  end
end
