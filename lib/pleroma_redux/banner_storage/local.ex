defmodule PleromaRedux.BannerStorage.Local do
  @behaviour PleromaRedux.BannerStorage

  @max_bytes 10_000_000

  @content_type_extensions %{
    "image/png" => ".png",
    "image/jpeg" => ".jpg",
    "image/webp" => ".webp",
    "image/gif" => ".gif"
  }

  @impl true
  def store_banner(user, %Plug.Upload{} = upload) do
    store_banner(user, upload, uploads_root())
  end

  def store_banner(%{id: user_id}, %Plug.Upload{} = upload, uploads_root)
      when is_integer(user_id) and is_binary(uploads_root) do
    with {:ok, ext} <- extension(upload),
         :ok <- validate_size(upload),
         {:ok, url_path} <- persist(upload, uploads_root, user_id, ext) do
      {:ok, url_path}
    end
  end

  defp uploads_root do
    priv_dir =
      :pleroma_redux
      |> :code.priv_dir()
      |> to_string()

    default = Path.join([priv_dir, "static", "uploads"])

    Application.get_env(:pleroma_redux, :uploads_dir, default)
  end

  defp validate_size(%Plug.Upload{path: path}) when is_binary(path) do
    case File.stat(path) do
      {:ok, %{size: size}} when size <= @max_bytes -> :ok
      {:ok, _} -> {:error, :file_too_large}
      {:error, reason} -> {:error, reason}
    end
  end

  defp extension(%Plug.Upload{content_type: content_type, filename: filename})
       when is_binary(content_type) and is_binary(filename) do
    case Map.fetch(@content_type_extensions, content_type) do
      {:ok, ext} -> {:ok, ext}
      :error -> {:error, :unsupported_media_type}
    end
  end

  defp persist(%Plug.Upload{path: path}, uploads_root, user_id, ext)
       when is_binary(path) and is_binary(uploads_root) do
    filename = "#{Ecto.UUID.generate()}#{ext}"
    relative_dir = Path.join(["uploads", "banners", Integer.to_string(user_id)])
    relative_path = Path.join(relative_dir, filename)
    destination_dir = Path.join([uploads_root, "banners", Integer.to_string(user_id)])
    destination_path = Path.join(destination_dir, filename)

    with :ok <- File.mkdir_p(destination_dir),
         :ok <- File.cp(path, destination_path) do
      {:ok, "/" <> relative_path}
    end
  end
end
