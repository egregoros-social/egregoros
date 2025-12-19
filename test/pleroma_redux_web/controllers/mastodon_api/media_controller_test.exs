defmodule PleromaReduxWeb.MastodonAPI.MediaControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  import Mox

  alias PleromaRedux.Objects
  alias PleromaRedux.Users

  test "POST /api/v1/media uploads media and returns attachment JSON", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    upload =
      %Plug.Upload{
        path: tmp_upload_path(),
        filename: "image.png",
        content_type: "image/png"
      }

    PleromaRedux.MediaStorage.Mock
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

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    upload =
      %Plug.Upload{
        path: tmp_upload_path(),
        filename: "image.png",
        content_type: "image/png"
      }

    PleromaRedux.MediaStorage.Mock
    |> expect(:store_media, fn ^user, %Plug.Upload{filename: "image.png"} ->
      {:ok, "/uploads/media/#{user.id}/image.png"}
    end)

    conn = post(conn, "/api/v2/media", %{"file" => upload})
    response = json_response(conn, 200)

    assert is_binary(response["id"])
    assert response["type"] == "image"
  end

  defp tmp_upload_path do
    path = Path.join(System.tmp_dir!(), "pleroma-redux-test-upload-#{Ecto.UUID.generate()}")
    File.write!(path, <<0, 1, 2, 3>>)
    path
  end
end
