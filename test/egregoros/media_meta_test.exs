defmodule Egregoros.MediaMetaTest do
  use ExUnit.Case, async: true

  alias Egregoros.MediaMeta

  test "mastodon_meta/1 returns dimensions for images" do
    upload =
      %Plug.Upload{
        path: fixture_path("DSCN0010.png"),
        filename: "DSCN0010.png",
        content_type: "image/png"
      }

    assert %{
             "original" => %{"width" => 640, "height" => 480},
             "small" => %{"width" => 400, "height" => 300}
           } = MediaMeta.mastodon_meta(upload)
  end

  test "blurhash/1 returns a blurhash for images" do
    upload =
      %Plug.Upload{
        path: fixture_path("DSCN0010.png"),
        filename: "DSCN0010.png",
        content_type: "image/png"
      }

    blurhash = MediaMeta.blurhash(upload)
    assert is_binary(blurhash)
    assert blurhash != ""
  end

  test "info/1 handles images with alpha channels" do
    path = tmp_alpha_png_path()

    upload =
      %Plug.Upload{
        path: path,
        filename: "alpha.png",
        content_type: "image/png"
      }

    {_meta, blurhash} = MediaMeta.info(upload)
    assert is_binary(blurhash) or is_nil(blurhash)
  end

  defp tmp_alpha_png_path do
    binary =
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO0pL9kAAAAASUVORK5CYII="
      |> Base.decode64!()

    path = Path.join(System.tmp_dir!(), "egregoros-alpha-#{Ecto.UUID.generate()}.png")
    File.write!(path, binary)
    path
  end

  defp fixture_path(filename) do
    Path.expand(Path.join(["test", "fixtures", filename]), File.cwd!())
  end
end
