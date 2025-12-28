defmodule EgregorosWeb.MastodonAPI.NotificationsController do
  use EgregorosWeb, :controller

  alias Egregoros.Notifications
  alias EgregorosWeb.MastodonAPI.Pagination
  alias EgregorosWeb.MastodonAPI.NotificationRenderer

  def index(conn, params) do
    user = conn.assigns.current_user
    pagination = Pagination.parse(params)

    activities =
      Notifications.list_for_user(user,
        limit: pagination.limit + 1,
        max_id: pagination.max_id,
        since_id: pagination.since_id,
        include_reactions?: false
      )

    has_more? = length(activities) > pagination.limit
    activities = Enum.take(activities, pagination.limit)

    conn
    |> Pagination.maybe_put_links(activities, has_more?, pagination)
    |> json(Enum.map(activities, &NotificationRenderer.render_notification(&1, user)))
  end
end
