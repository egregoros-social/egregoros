defmodule PleromaReduxWeb.Attachments do
  @moduledoc false

  @image_exts ~w(.apng .avif .bmp .gif .heic .heif .jpeg .jpg .png .svg .webp)
  @video_exts ~w(.m4v .mov .mp4 .ogv .webm)
  @audio_exts ~w(.aac .flac .m4a .mp3 .ogg .opus .wav)

  def kind(%{} = attachment) do
    media_type = media_type(attachment)
    href = href(attachment)

    media_kind =
      cond do
        is_binary(media_type) and String.starts_with?(media_type, "video/") -> :video
        is_binary(media_type) and String.starts_with?(media_type, "audio/") -> :audio
        is_binary(media_type) and String.starts_with?(media_type, "image/") -> :image
        true -> :link
      end

    ext_kind = kind_from_href(href)

    cond do
      media_kind == :link and ext_kind != :link -> ext_kind
      media_kind == :image and ext_kind in [:video, :audio] -> ext_kind
      true -> media_kind
    end
  end

  def kind(_attachment), do: :link

  def media?(attachment) do
    kind(attachment) in [:image, :video, :audio]
  end

  def source_type(attachment, fallback) when is_binary(fallback) and fallback != "" do
    case media_type(attachment) do
      media_type when is_binary(media_type) and media_type != "" -> media_type
      _ -> fallback
    end
  end

  defp media_type(%{} = attachment) do
    case Map.get(attachment, :media_type) || Map.get(attachment, "mediaType") do
      media_type when is_binary(media_type) ->
        media_type = String.trim(media_type)
        if media_type == "", do: nil, else: media_type

      _ ->
        nil
    end
  end

  defp media_type(_attachment), do: nil

  defp href(%{} = attachment) do
    case Map.get(attachment, :href) || Map.get(attachment, "href") do
      href when is_binary(href) ->
        href = String.trim(href)
        if href == "", do: nil, else: href

      _ ->
        nil
    end
  end

  defp href(_attachment), do: nil

  defp kind_from_href(href) when is_binary(href) and href != "" do
    ext =
      href
      |> URI.parse()
      |> then(fn
        %URI{path: path} when is_binary(path) -> Path.extname(path)
        _ -> Path.extname(href)
      end)
      |> String.downcase()

    cond do
      ext in @image_exts -> :image
      ext in @video_exts -> :video
      ext in @audio_exts -> :audio
      true -> :link
    end
  end

  defp kind_from_href(_href), do: :link
end

