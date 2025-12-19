defmodule PleromaReduxWeb.MastodonAPI.FollowsControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  import Mox

  alias PleromaRedux.Users

  test "POST /api/v1/follows follows a remote account by handle", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    actor_url = "https://remote.example/users/bob"

    PleromaRedux.HTTP.Mock
    |> expect(:get, fn url, _headers ->
      assert url ==
               "https://remote.example/.well-known/webfinger?resource=acct:bob@remote.example"

      {:ok,
       %{
         status: 200,
         body: %{
           "links" => [
             %{
               "rel" => "self",
               "type" => "application/activity+json",
               "href" => actor_url
             }
           ]
         },
         headers: []
       }}
    end)
    |> expect(:get, fn url, _headers ->
      assert url == actor_url

      {:ok,
       %{
         status: 200,
         body: %{
           "id" => actor_url,
           "type" => "Person",
           "preferredUsername" => "bob",
           "inbox" => "https://remote.example/users/bob/inbox",
           "outbox" => "https://remote.example/users/bob/outbox",
           "publicKey" => %{
             "id" => actor_url <> "#main-key",
             "owner" => actor_url,
             "publicKeyPem" => "-----BEGIN PUBLIC KEY-----\nMIIB...\n-----END PUBLIC KEY-----\n"
           }
         },
         headers: []
       }}
    end)
    |> expect(:post, fn url, body, _headers ->
      assert url == "https://remote.example/users/bob/inbox"

      decoded = Jason.decode!(body)
      assert decoded["type"] == "Follow"
      assert decoded["actor"] == user.ap_id
      assert decoded["object"] == actor_url

      {:ok, %{status: 202, body: "", headers: []}}
    end)

    conn = post(conn, "/api/v1/follows", %{"uri" => "bob@remote.example"})
    response = json_response(conn, 200)

    assert response["username"] == "bob"
    assert response["acct"] == "bob@remote.example"
  end
end

