defmodule PleromaReduxWeb.MastodonAPI.TimelinesController do
  use PleromaReduxWeb, :controller

  alias PleromaRedux.Objects
  alias PleromaReduxWeb.MastodonAPI.Pagination
  alias PleromaReduxWeb.MastodonAPI.StatusRenderer

  def public(conn, params) do
    pagination = Pagination.parse(params)

    objects =
      Objects.list_notes(
        limit: pagination.limit + 1,
        max_id: pagination.max_id,
        since_id: pagination.since_id
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
      Objects.list_home_notes(user.ap_id,
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
end
