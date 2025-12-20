defmodule PleromaReduxWeb.StatusLiveTest do
  use PleromaReduxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PleromaRedux.Activities.Note
  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Users

  setup do
    {:ok, user} = Users.create_local_user("alice")
    %{user: user}
  end

  test "renders a local status permalink page", %{conn: conn, user: user} do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Hello from status"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    assert has_element?(view, "article[data-role='status-card']", "Hello from status")
  end

  test "renders thread context around the status", %{conn: conn, user: user} do
    assert {:ok, root} = Pipeline.ingest(Note.build(user, "Root"), local: true)

    assert {:ok, reply} =
             Pipeline.ingest(
               Note.build(user, "Reply") |> Map.put("inReplyTo", root.ap_id),
               local: true
             )

    assert {:ok, _child} =
             Pipeline.ingest(
               Note.build(user, "Child") |> Map.put("inReplyTo", reply.ap_id),
               local: true
             )

    uuid = uuid_from_ap_id(reply.ap_id)

    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    html = render(view)

    assert html =~ "Root"
    assert html =~ "Reply"
    assert html =~ "Child"

    root_index = binary_index!(html, "Root")
    reply_index = binary_index!(html, "Reply")
    child_index = binary_index!(html, "Child")

    assert root_index < reply_index
    assert reply_index < child_index
  end

  test "signed-in users can reply from the status page", %{conn: conn, user: user} do
    assert {:ok, parent} = Pipeline.ingest(Note.build(user, "Parent post"), local: true)
    uuid = uuid_from_ap_id(parent.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}?reply=true")

    view
    |> form("#reply-form", reply: %{content: "A reply"})
    |> render_submit()

    assert has_element?(view, "article", "A reply")

    [reply] = Objects.list_replies_to(parent.ap_id, limit: 1)
    assert reply.data["inReplyTo"] == parent.ap_id
  end

  test "signed-in users can like posts from the status page", %{conn: conn, user: user} do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Like me"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    refute Objects.get_by_type_actor_object("Like", user.ap_id, note.ap_id)

    view
    |> element("#post-#{note.id} button[data-role='like']")
    |> render_click()

    assert Objects.get_by_type_actor_object("Like", user.ap_id, note.ap_id)
    assert has_element?(view, "#post-#{note.id} button[data-role='like']", "Unlike")
  end

  test "signed-in users can repost posts from the status page", %{conn: conn, user: user} do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "Boost me"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    refute Objects.get_by_type_actor_object("Announce", user.ap_id, note.ap_id)

    view
    |> element("#post-#{note.id} button[data-role='repost']")
    |> render_click()

    assert Objects.get_by_type_actor_object("Announce", user.ap_id, note.ap_id)
    assert has_element?(view, "#post-#{note.id} button[data-role='repost']", "Unrepost")
  end

  test "signed-in users can react to posts from the status page", %{conn: conn, user: user} do
    assert {:ok, note} = Pipeline.ingest(Note.build(user, "React to me"), local: true)
    uuid = uuid_from_ap_id(note.ap_id)

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id})
    assert {:ok, view, _html} = live(conn, "/@alice/#{uuid}")

    refute Objects.get_emoji_react(user.ap_id, note.ap_id, "🔥")

    view
    |> element("#post-#{note.id} button[data-role='reaction'][data-emoji='🔥']")
    |> render_click()

    assert Objects.get_emoji_react(user.ap_id, note.ap_id, "🔥")

    assert has_element?(
             view,
             "#post-#{note.id} button[data-role='reaction'][data-emoji='🔥']",
             "1"
           )
  end

  defp uuid_from_ap_id(ap_id) when is_binary(ap_id) do
    case URI.parse(ap_id) do
      %URI{path: path} when is_binary(path) and path != "" -> Path.basename(path)
      _ -> Path.basename(ap_id)
    end
  end

  defp binary_index!(binary, pattern) when is_binary(binary) and is_binary(pattern) do
    case :binary.match(binary, pattern) do
      {index, _length} -> index
      :nomatch -> raise ArgumentError, "pattern not found: #{inspect(pattern)}"
    end
  end
end
