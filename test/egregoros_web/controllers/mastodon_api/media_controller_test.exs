defmodule EgregorosWeb.MastodonAPI.MediaControllerTest do
  use EgregorosWeb.ConnCase, async: true

  import Mox

  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Repo
  alias Egregoros.Users

  test "POST /api/v1/media uploads media and returns attachment JSON", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    upload =
      %Plug.Upload{
        path: fixture_path("DSCN0010.png"),
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
    assert is_binary(response["preview_url"])
    assert response["preview_url"] != response["url"]
    assert String.ends_with?(response["preview_url"], "/uploads/media/#{user.id}/image-thumb.jpg")
    assert is_binary(response["blurhash"])

    assert %{
             "original" => %{"width" => 640, "height" => 480},
             "small" => %{"width" => 400, "height" => 300}
           } = response["meta"]

    assert %{} = Objects.get(response["id"])
  end

  test "POST /api/v1/media returns 422 when file is missing", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    conn = post(conn, "/api/v1/media", %{})

    assert response(conn, 422) =~ "Unprocessable Entity"
  end

  test "POST /api/v1/media returns 422 when storage fails", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    upload =
      %Plug.Upload{
        path: fixture_path("DSCN0010.png"),
        filename: "image.png",
        content_type: "image/png"
      }

    Egregoros.MediaStorage.Mock
    |> expect(:store_media, fn ^user, %Plug.Upload{filename: "image.png"} ->
      {:error, :nope}
    end)

    conn = post(conn, "/api/v1/media", %{"file" => upload})

    assert response(conn, 422) =~ "Unprocessable Entity"
  end

  test "POST /api/v2/media uploads media and returns attachment JSON", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    upload =
      %Plug.Upload{
        path: fixture_path("DSCN0010.png"),
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

  test "PUT /api/v1/media/:id returns 404 for unknown media ids", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    conn = put(conn, "/api/v1/media/not-a-flake-id", %{"description" => "Alt text"})
    assert response(conn, 404) =~ "Not Found"
  end

  test "PUT /api/v1/media/:id returns 404 when media is not owned by user", %{conn: conn} do
    {:ok, owner} = Users.create_local_user("media-owner")
    {:ok, other} = Users.create_local_user("media-other")

    {:ok, media_object} =
      %Object{}
      |> Object.changeset(%{
        ap_id: "https://example.com/media/" <> Ecto.UUID.generate(),
        type: "Image",
        actor: owner.ap_id,
        data: %{"url" => "https://example.com/uploads/file.png"},
        local: true
      })
      |> Repo.insert()

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, other} end)

    conn = put(conn, "/api/v1/media/#{media_object.id}", %{"description" => "Alt text"})
    assert response(conn, 404) =~ "Not Found"

    assert is_nil(Objects.get(media_object.id).data["name"])
  end

  test "PUT /api/v1/media/:id returns 404 when description is missing", %{conn: conn} do
    {:ok, user} = Users.create_local_user("media-no-description")

    {:ok, media_object} =
      %Object{}
      |> Object.changeset(%{
        ap_id: "https://example.com/media/" <> Ecto.UUID.generate(),
        type: "Image",
        actor: user.ap_id,
        data: %{"url" => "https://example.com/uploads/file.png"},
        local: true
      })
      |> Repo.insert()

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    conn = put(conn, "/api/v1/media/#{media_object.id}", %{})
    assert response(conn, 404) =~ "Not Found"
    assert is_nil(Objects.get(media_object.id).data["name"])
  end

  defp tmp_upload_path do
    path = Path.join(System.tmp_dir!(), "egregoros-test-upload-#{Ecto.UUID.generate()}")
    File.write!(path, <<0, 1, 2, 3>>)
    path
  end

  defp fixture_path(filename) do
    Path.expand(Path.join(["test", "fixtures", filename]), File.cwd!())
  end
end
