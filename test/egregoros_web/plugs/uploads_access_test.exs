defmodule EgregorosWeb.Plugs.UploadsAccessTest do
  use EgregorosWeb.ConnCase, async: false

  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Users
  alias EgregorosWeb.Endpoint

  test "private/direct media is only accessible to the owner or recipients", %{conn: conn} do
    {:ok, author} = Users.create_local_user("author")
    {:ok, recipient} = Users.create_local_user("recipient")
    {:ok, other} = Users.create_local_user("other")

    filename = "uploads-access-test.png"
    url_path = "/uploads/media/#{author.id}/#{filename}"

    uploads_root = Application.fetch_env!(:egregoros, :uploads_dir)

    media_dir = Path.join([uploads_root, "media", Integer.to_string(author.id)])
    File.mkdir_p!(media_dir)
    file_path = Path.join(media_dir, filename)
    File.write!(file_path, "ok")
    assert File.exists?(file_path)

    on_exit(fn ->
      File.rm_rf!(Path.join([uploads_root, "media", Integer.to_string(author.id)]))
    end)

    media_ap_id = Endpoint.url() <> "/objects/" <> Ecto.UUID.generate()

    {:ok, media} =
      Objects.create_object(%{
        ap_id: media_ap_id,
        type: "Image",
        actor: author.ap_id,
        local: true,
        published: DateTime.utc_now(),
        data: %{
          "id" => media_ap_id,
          "type" => "Image",
          "mediaType" => "image/png",
          "url" => [
            %{
              "type" => "Link",
              "mediaType" => "image/png",
              "href" => url_path
            }
          ]
        }
      })

    {:ok, _note} =
      Pipeline.ingest(
        %{
          "id" => Endpoint.url() <> "/objects/" <> Ecto.UUID.generate(),
          "type" => "Note",
          "actor" => author.ap_id,
          "content" => "hello",
          "to" => [recipient.ap_id],
          "cc" => [],
          "attachment" => [media.data]
        },
        local: true
      )

    assert response(get(conn, url_path), 404) == "Not Found"

    recipient_conn = Plug.Test.init_test_session(conn, %{user_id: recipient.id})
    assert response(get(recipient_conn, url_path), 200) == "ok"

    other_conn = Plug.Test.init_test_session(conn, %{user_id: other.id})
    assert response(get(other_conn, url_path), 404) == "Not Found"

    owner_conn = Plug.Test.init_test_session(conn, %{user_id: author.id})
    assert response(get(owner_conn, url_path), 200) == "ok"
  end
end
