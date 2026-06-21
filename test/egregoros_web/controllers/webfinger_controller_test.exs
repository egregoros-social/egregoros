defmodule EgregorosWeb.WebFingerControllerTest do
  use EgregorosWeb.ConnCase, async: true

  alias Egregoros.Federation.InstanceActor
  alias Egregoros.Users
  alias Egregoros.VerifiableCredentials.DidWeb
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

  test "GET /.well-known/webfinger returns 400 when resource is missing", %{conn: conn} do
    conn = get(conn, "/.well-known/webfinger")
    assert response(conn, 400) == "Bad Request"
  end

  test "GET /.well-known/webfinger returns 404 for unknown local user", %{conn: conn} do
    host = Endpoint.url() |> URI.parse() |> Map.fetch!(:host)
    conn = get(conn, "/.well-known/webfinger", resource: "acct:doesnotexist@#{host}")
    assert response(conn, 404) == "Not Found"
  end

  test "GET /.well-known/webfinger resolves a local user by ap_id resource", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")

    conn = get(conn, "/.well-known/webfinger", resource: user.ap_id)
    body = json_response(conn, 200)

    assert body["aliases"] == [user.ap_id]

    self_link =
      Enum.find(body["links"], fn link ->
        link["rel"] == "self" and link["type"] == "application/activity+json"
      end)

    assert self_link["href"] == user.ap_id
  end

  test "GET /.well-known/webfinger resolves the instance actor by did:web resource", %{conn: conn} do
    {:ok, instance_actor} = InstanceActor.get_actor()
    did = DidWeb.instance_did()

    domain =
      Endpoint.url()
      |> URI.parse()
      |> Egregoros.Domain.from_uri()

    conn = get(conn, "/.well-known/webfinger", resource: did)
    body = json_response(conn, 200)

    assert body["subject"] == "acct:#{instance_actor.nickname}@#{domain}"
    assert Enum.sort(body["aliases"]) == Enum.sort([instance_actor.ap_id, did])

    self_link =
      Enum.find(body["links"], fn link ->
        link["rel"] == "self" and link["type"] == "application/activity+json"
      end)

    assert self_link["href"] == instance_actor.ap_id
  end
end
