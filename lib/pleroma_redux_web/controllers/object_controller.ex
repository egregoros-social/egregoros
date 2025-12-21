defmodule PleromaReduxWeb.ObjectController do
  use PleromaReduxWeb, :controller

  alias PleromaRedux.Objects
  alias PleromaReduxWeb.Endpoint

  def show(conn, %{"uuid" => uuid}) do
    ap_id = Endpoint.url() <> "/objects/" <> uuid

    case Objects.get_by_ap_id(ap_id) do
      %{local: true} = object ->
        data = Map.put_new(object.data, "@context", "https://www.w3.org/ns/activitystreams")

        conn
        |> put_resp_content_type("application/activity+json")
        |> send_resp(200, Jason.encode!(data))

      _ ->
        send_resp(conn, 404, "Not found")
    end
  end
end
