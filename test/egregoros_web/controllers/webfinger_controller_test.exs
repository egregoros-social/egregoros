defmodule EgregorosWeb.WebFingerControllerTest do
  use EgregorosWeb.ConnCase, async: true

  alias Egregoros.Users
  alias EgregorosWeb.Endpoint

  test "GET /.well-known/webfinger returns local user", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")

    host = Endpoint.url() |> URI.parse() |> Map.fetch!(:host)
    resource = "acct:#{user.nickname}@#{host}"

    conn = get(conn, "/.well-known/webfinger", resource: resource)
    body = json_response(conn, 200)

    assert body["subject"] == resource

    self_link =
      Enum.find(body["links"], fn link ->
        link["rel"] == "self" and link["type"] == "application/activity+json"
      end)

    assert self_link["href"] == user.ap_id
  end

  test "GET /.well-known/webfinger returns local user when resource includes port", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")

    domain =
      Endpoint.url()
      |> URI.parse()
      |> Egregoros.Domain.from_uri()

    resource = "acct:#{user.nickname}@#{domain}"

    conn = get(conn, "/.well-known/webfinger", resource: resource)
    body = json_response(conn, 200)

    assert body["subject"] == resource

    self_link =
      Enum.find(body["links"], fn link ->
        link["rel"] == "self" and link["type"] == "application/activity+json"
      end)

    assert self_link["href"] == user.ap_id
  end
end
