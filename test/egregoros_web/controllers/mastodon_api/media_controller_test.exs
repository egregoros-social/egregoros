defmodule EgregorosWeb.MastodonAPI.MediaControllerTest do
  use EgregorosWeb.ConnCase, async: true

  import Mox

  alias Egregoros.Objects
  alias Egregoros.Users

  test "POST /api/v1/media uploads media and returns attachment JSON", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    upload =
      %Plug.Upload{
        path: tmp_upload_path(),
        filename: "image.png",
        content_type: "image/png"
      }

    Egregoros.MediaStorage.Mock
    |> expect(:store_media, fn ^user, %Plug.Upload{filename: "image.png"} ->
      {:ok, "/uploads/media/#{user.id}/image.png"}
    end)

    conn = post(conn, "/api/v1/media", %{"file" => upload})
    response = json_response(conn, 200)

    assert is_binary(response["id"])
    assert response["type"] == "image"
    assert String.ends_with?(response["url"], "/uploads/media/#{user.id}/image.png")
    assert response["preview_url"] == response["url"]

    assert %{} = Objects.get(response["id"])
  end

  test "POST /api/v2/media uploads media and returns attachment JSON", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    upload =
      %Plug.Upload{
        path: tmp_upload_path(),
        filename: "image.png",
        content_type: "image/png"
      }

    Egregoros.MediaStorage.Mock
    |> expect(:store_media, fn ^user, %Plug.Upload{filename: "image.png"} ->
      {:ok, "/uploads/media/#{user.id}/image.png"}
    end)

    conn = post(conn, "/api/v2/media", %{"file" => upload})
    response = json_response(conn, 200)

    assert is_binary(response["id"])
    assert response["type"] == "image"
  end

  test "PUT /api/v1/media/:id updates media description", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    Egregoros.Auth.Mock
    |> expect(:current_user, 2, fn _conn -> {:ok, user} end)

    upload =
      %Plug.Upload{
        path: tmp_upload_path(),
        filename: "image.png",
        content_type: "image/png"
      }

    Egregoros.MediaStorage.Mock
    |> expect(:store_media, fn ^user, %Plug.Upload{filename: "image.png"} ->
      {:ok, "/uploads/media/#{user.id}/image.png"}
    end)

    conn = post(conn, "/api/v1/media", %{"file" => upload})
    response = json_response(conn, 200)
    id = response["id"]

    conn = put(conn, "/api/v1/media/#{id}", %{"description" => "Alt text"})
    response = json_response(conn, 200)

    assert response["id"] == id
    assert response["description"] == "Alt text"

    assert Objects.get(id).data["name"] == "Alt text"
  end

  defp tmp_upload_path do
    path = Path.join(System.tmp_dir!(), "egregoros-test-upload-#{Ecto.UUID.generate()}")
    File.write!(path, <<0, 1, 2, 3>>)
    path
  end
end
