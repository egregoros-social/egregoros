defmodule PleromaRedux.Media do
  import Ecto.Query, only: [from: 2]

  alias PleromaRedux.Object
  alias PleromaRedux.Repo
  alias PleromaRedux.User
  alias PleromaRedux.Objects
  alias PleromaReduxWeb.Endpoint
  alias PleromaReduxWeb.URL

  @allowed_types ~w(Document Image)

  def create_media_object(%User{} = user, %Plug.Upload{} = upload, url_path, opts \\ [])
      when is_binary(url_path) and is_list(opts) do
    ap_id = Endpoint.url() <> "/objects/" <> Ecto.UUID.generate()
    href = URL.absolute(url_path) || url_path

    description =
      opts
      |> Keyword.get(:description, "")
      |> to_string()
      |> String.trim()

    Objects.create_object(%{
      ap_id: ap_id,
      type: activity_type(upload.content_type),
      actor: user.ap_id,
      local: true,
      published: DateTime.utc_now(),
      data: %{
        "id" => ap_id,
        "type" => activity_type(upload.content_type),
        "mediaType" => upload.content_type,
        "url" => [
          %{
            "type" => "Link",
            "mediaType" => upload.content_type,
            "href" => href
          }
        ],
        "name" => description
      }
    })
  end

  def attachments_from_ids(%User{} = user, ids) do
    ids = List.wrap(ids)

    with {:ok, int_ids} <- parse_ids(ids),
         {:ok, objects} <- fetch_owned_media(user, int_ids) do
      attachments =
        int_ids
        |> Enum.map(fn id -> Map.fetch!(objects, id) end)
        |> Enum.map(& &1.data)

      {:ok, attachments}
    end
  end

  def attachments_from_ids(_user, _ids), do: {:ok, []}

  defp parse_ids(ids) when is_list(ids) do
    parsed =
      Enum.map(ids, fn
        id when is_integer(id) -> id
        id when is_binary(id) -> parse_int(id)
        _ -> nil
      end)

    if Enum.any?(parsed, &is_nil/1) do
      {:error, :invalid_media_id}
    else
      {:ok, parsed}
    end
  end

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp fetch_owned_media(_user, []), do: {:ok, %{}}

  defp fetch_owned_media(%User{} = user, ids) when is_list(ids) do
    records =
      from(o in Object,
        where: o.id in ^ids and o.actor == ^user.ap_id and o.type in ^@allowed_types,
        select: o
      )
      |> Repo.all()

    objects = Map.new(records, &{&1.id, &1})

    if map_size(objects) == length(ids) do
      {:ok, objects}
    else
      {:error, :not_found}
    end
  end

  defp activity_type(content_type) when is_binary(content_type) do
    if String.starts_with?(content_type, "image/"), do: "Image", else: "Document"
  end

  defp activity_type(_), do: "Document"
end
