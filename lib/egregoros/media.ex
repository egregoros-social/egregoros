defmodule Egregoros.Media do
  import Ecto.Query, only: [from: 2]

  alias Egregoros.Object
  alias Egregoros.Repo
  alias Egregoros.User
  alias Egregoros.Objects
  alias EgregorosWeb.Endpoint
  alias EgregorosWeb.URL

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

  def local_href_visible_to?(href, user) when is_binary(href) do
    case get_local_media_by_href(href) do
      %Object{} = media ->
        visible_to_user?(media, user)

      _ ->
        false
    end
  end

  def local_href_visible_to?(_href, _user), do: false

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

  defp get_local_media_by_href(href) when is_binary(href) do
    href = String.trim(href)
    absolute = URL.absolute(href)

    from(o in Object,
      where:
        o.local == true and o.type in ^@allowed_types and
          (fragment("? @> ?", o.data, ^%{"url" => [%{"href" => href}]}) or
             fragment("? @> ?", o.data, ^%{"url" => [%{"href" => absolute}]})),
      limit: 1
    )
    |> Repo.one()
  end

  defp get_local_media_by_href(_href), do: nil

  defp visible_to_user?(%Object{} = media, %User{} = user) do
    if media.actor == user.ap_id do
      true
    else
      visible_via_attached_note?(media, user)
    end
  end

  defp visible_to_user?(%Object{} = media, nil) do
    visible_via_attached_note?(media, nil)
  end

  defp visible_to_user?(%Object{} = media, _other) do
    visible_via_attached_note?(media, nil)
  end

  defp visible_via_attached_note?(%Object{} = media, user) do
    media.ap_id
    |> notes_referencing_attachment()
    |> Enum.any?(&Objects.visible_to?(&1, user))
  end

  defp notes_referencing_attachment(media_ap_id) when is_binary(media_ap_id) do
    from(o in Object,
      where:
        o.type == "Note" and
          fragment("? @> ?", o.data, ^%{"attachment" => [%{"id" => media_ap_id}]}),
      order_by: [desc: o.id],
      limit: 20
    )
    |> Repo.all()
  end

  defp notes_referencing_attachment(_media_ap_id), do: []
end
