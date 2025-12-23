defmodule PleromaReduxWeb.SearchLiveTest do
  use PleromaReduxWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest

  alias PleromaRedux.Activities.Note
  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Users

  test "searching by query lists matching accounts", %{conn: conn} do
    {:ok, _} = Users.create_local_user("alice")
    {:ok, _} = Users.create_local_user("bob")

    {:ok, view, _html} = live(conn, "/search?q=bo")

    assert has_element?(view, "[data-role='search-results']")
    assert has_element?(view, "[data-role='search-result-handle']", "@bob")
    refute has_element?(view, "[data-role='search-result-handle']", "@alice")
  end

  test "searching by query lists matching posts", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")
    assert {:ok, _} = Pipeline.ingest(Note.build(user, "Hello from search"), local: true)
    assert {:ok, _} = Pipeline.ingest(Note.build(user, "No match here"), local: true)

    {:ok, view, _html} = live(conn, "/search?q=hello")

    assert has_element?(view, "[data-role='search-post-results']")
    assert has_element?(view, "[data-role='status-card']", "Hello from search")
    refute has_element?(view, "[data-role='status-card']", "No match here")
  end

  test "searching by query does not include direct messages", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")

    assert {:ok, _} = Pipeline.ingest(Note.build(user, "Public hello"), local: true)

    dm =
      user
      |> Note.build("Secret hello")
      |> Map.put("to", [])
      |> Map.put("cc", [])

    assert {:ok, _} = Pipeline.ingest(dm, local: true)

    {:ok, view, _html} = live(conn, "/search?q=secret")

    assert has_element?(view, "[data-role='search-post-results']")
    refute has_element?(view, "[data-role='status-card']", "Secret hello")
  end

  test "searching for a hashtag shows a tag quick link", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")
    assert {:ok, _} = Pipeline.ingest(Note.build(user, "Hello #elixir"), local: true)

    {:ok, view, _html} = live(conn, "/search?q=%23elixir")

    assert has_element?(view, "[data-role='search-tag-results']")
    assert has_element?(view, "[data-role='search-tag-link'][href='/tags/elixir']", "#elixir")
  end

  test "searching without # still suggests a matching tag", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")
    assert {:ok, _} = Pipeline.ingest(Note.build(user, "Hello #elixir"), local: true)

    {:ok, view, _html} = live(conn, "/search?q=elixir")

    assert has_element?(view, "[data-role='search-tag-results']")
    assert has_element?(view, "[data-role='search-tag-link'][href='/tags/elixir']", "#elixir")
  end

  test "reply buttons dispatch reply modal events without navigation", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")
    assert {:ok, _} = Pipeline.ingest(Note.build(user, "Reply target"), local: true)
    [note] = Objects.list_notes()

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/search?q=reply")

    assert has_element?(view, "#reply-modal[data-role='reply-modal'][data-state='closed']")
    assert has_element?(view, "#search-post-#{note.id} button[data-role='reply']")

    html =
      view
      |> element("#search-post-#{note.id} button[data-role='reply']")
      |> render()

    assert html =~ "predux:reply-open"
    refute html =~ "?reply=true"
  end

  test "signed-in users can reply from search results", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")
    assert {:ok, parent} = Pipeline.ingest(Note.build(user, "Parent post"), local: true)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/search?q=parent")

    view
    |> element("#search-post-#{parent.id} button[data-role='reply']")
    |> render_click()

    view
    |> form("#reply-modal-form", reply: %{content: "A reply"})
    |> render_submit()

    [reply] = Objects.list_replies_to(parent.ap_id, limit: 1)
    assert reply.data["inReplyTo"] == parent.ap_id
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
