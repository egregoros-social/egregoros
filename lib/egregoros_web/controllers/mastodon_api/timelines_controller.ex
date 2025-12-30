defmodule EgregorosWeb.MastodonAPI.TimelinesController do
  use EgregorosWeb, :controller

  alias Egregoros.Objects
  alias EgregorosWeb.MastodonAPI.Pagination
  alias EgregorosWeb.MastodonAPI.StatusRenderer

  def public(conn, params) do
    pagination = Pagination.parse(params)
    local_only? = truthy?(Map.get(params, "local"))
    remote_only? = truthy?(Map.get(params, "remote"))
    only_media? = truthy?(Map.get(params, "only_media"))

    objects =
      Objects.list_public_statuses(
        limit: pagination.limit + 1,
        max_id: pagination.max_id,
        since_id: pagination.since_id,
        local: local_only?,
        remote: remote_only?,
        only_media: only_media?
      )

    has_more? = length(objects) > pagination.limit
    objects = Enum.take(objects, pagination.limit)

    conn
    |> Pagination.maybe_put_links(objects, has_more?, pagination)
    |> json(StatusRenderer.render_statuses(objects))
  end

  def home(conn, params) do
    pagination = Pagination.parse(params)
    user = conn.assigns.current_user

    objects =
      Objects.list_home_statuses(user.ap_id,
        limit: pagination.limit + 1,
        max_id: pagination.max_id,
        since_id: pagination.since_id
      )

    has_more? = length(objects) > pagination.limit
    objects = Enum.take(objects, pagination.limit)

    conn
    |> Pagination.maybe_put_links(objects, has_more?, pagination)
    |> json(StatusRenderer.render_statuses(objects, user))
  end

  def tag(conn, %{"hashtag" => hashtag} = params) do
    pagination = Pagination.parse(params)
    local_only? = truthy?(Map.get(params, "local"))
    remote_only? = truthy?(Map.get(params, "remote"))
    only_media? = truthy?(Map.get(params, "only_media"))

    hashtag =
      hashtag
      |> to_string()
      |> String.trim()
      |> String.trim_leading("#")

    objects =
      Objects.list_public_statuses_by_hashtag(hashtag,
        limit: pagination.limit + 1,
        max_id: pagination.max_id,
        since_id: pagination.since_id,
        local: local_only?,
        remote: remote_only?,
        only_media: only_media?
      )

    has_more? = length(objects) > pagination.limit
    objects = Enum.take(objects, pagination.limit)

    conn
    |> Pagination.maybe_put_links(objects, has_more?, pagination)
    |> json(StatusRenderer.render_statuses(objects))
  end

  defp truthy?(value) do
    case value do
      true -> true
      1 -> true
      "1" -> true
      "true" -> true
      _ -> false
    end
  end
end
