defmodule PleromaReduxWeb.NodeinfoController do
  use PleromaReduxWeb, :controller

  alias PleromaReduxWeb.Endpoint

  def nodeinfo_index(conn, _params) do
    json(conn, %{
      "links" => [
        %{
          "rel" => "http://nodeinfo.diaspora.software/ns/schema/2.0",
          "href" => Endpoint.url() <> "/nodeinfo/2.0.json"
        }
      ]
    })
  end

  def nodeinfo(conn, _params) do
    conn
    |> put_resp_content_type(
      "application/json; profile=http://nodeinfo.diaspora.software/ns/schema/2.0#; charset=utf-8"
    )
    |> json(%{
      "version" => "2.0",
      "software" => %{
        "name" => "pleroma_redux",
        "version" => "0.1.0"
      },
      "protocols" => ["activitypub"],
      "services" => %{"inbound" => [], "outbound" => []},
      "openRegistrations" => false,
      "usage" => %{"users" => %{"total" => 0}, "localPosts" => 0},
      "metadata" => %{}
    })
  end
end
