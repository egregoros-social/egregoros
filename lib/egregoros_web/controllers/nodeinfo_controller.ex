defmodule EgregorosWeb.NodeinfoController do
  use EgregorosWeb, :controller

  import Ecto.Query, only: [from: 2]

  alias Egregoros.Object
  alias Egregoros.Repo
  alias Egregoros.User
  alias EgregorosWeb.Endpoint

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
    user_count =
      from(u in User, where: u.local == true)
      |> Repo.aggregate(:count, :id)

    local_posts =
      from(o in Object, where: o.type == "Note" and o.local == true)
      |> Repo.aggregate(:count, :id)

    conn
    |> put_resp_content_type(
      "application/json; profile=http://nodeinfo.diaspora.software/ns/schema/2.0#; charset=utf-8"
    )
    |> json(%{
      "version" => "2.0",
      "software" => %{
        "name" => "egregoros",
        "version" => app_version()
      },
      "protocols" => ["activitypub"],
      "services" => %{"inbound" => [], "outbound" => []},
      "openRegistrations" => true,
      "usage" => %{"users" => %{"total" => user_count}, "localPosts" => local_posts},
      "metadata" => %{}
    })
  end

  defp app_version do
    case Application.spec(:egregoros, :vsn) do
      nil -> "0.0.0"
      vsn -> to_string(vsn)
    end
  end
end
