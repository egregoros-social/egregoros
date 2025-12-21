defmodule PleromaReduxWeb.SearchLiveTest do
  use PleromaReduxWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest

  alias PleromaRedux.Users

  test "searching by query lists matching accounts", %{conn: conn} do
    {:ok, _} = Users.create_local_user("alice")
    {:ok, _} = Users.create_local_user("bob")

    {:ok, view, _html} = live(conn, "/search?q=bo")

    assert has_element?(view, "[data-role='search-results']")
    assert has_element?(view, "[data-role='search-result-handle']", "@bob")
    refute has_element?(view, "[data-role='search-result-handle']", "@alice")
  end

  test "logged-in users can follow remote accounts by handle", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")

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

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})

    {:ok, view, _html} = live(conn, "/search?q=bob@remote.example")

    assert has_element?(view, "[data-role='remote-follow']")

    view
    |> element("button[data-role='remote-follow-button']")
    |> render_click()

    assert has_element?(view, "[data-role='search-result-handle']", "@bob@remote.example")
  end
end
