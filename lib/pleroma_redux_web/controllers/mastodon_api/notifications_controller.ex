defmodule PleromaReduxWeb.MastodonAPI.NotificationsController do
  use PleromaReduxWeb, :controller

  alias PleromaRedux.Notifications
  alias PleromaRedux.Objects
  alias PleromaRedux.Object
  alias PleromaRedux.User
  alias PleromaRedux.Users
  alias PleromaReduxWeb.MastodonAPI.AccountRenderer
  alias PleromaReduxWeb.MastodonAPI.Pagination
  alias PleromaReduxWeb.MastodonAPI.StatusRenderer

  def index(conn, params) do
    user = conn.assigns.current_user
    pagination = Pagination.parse(params)

    activities =
      Notifications.list_for_user(user,
        limit: pagination.limit + 1,
        max_id: pagination.max_id,
        since_id: pagination.since_id
      )

    has_more? = length(activities) > pagination.limit
    activities = Enum.take(activities, pagination.limit)

    conn
    |> Pagination.maybe_put_links(activities, has_more?, pagination)
    |> json(Enum.map(activities, &render_notification(&1, user)))
  end

  defp render_notification(%Object{} = activity, %User{} = current_user) do
    status =
      case activity.type do
        "Like" -> Objects.get_by_ap_id(activity.object)
        "Announce" -> Objects.get_by_ap_id(activity.object)
        _ -> nil
      end

    %{
      "id" => Integer.to_string(activity.id),
      "type" => mastodon_type(activity.type),
      "created_at" => format_datetime(activity),
      "account" => AccountRenderer.render_account(account_for_actor(activity.actor)),
      "status" => if(status, do: StatusRenderer.render_status(status, current_user), else: nil)
    }
  end

  defp mastodon_type("Follow"), do: "follow"
  defp mastodon_type("Like"), do: "favourite"
  defp mastodon_type("Announce"), do: "reblog"
  defp mastodon_type(type) when is_binary(type), do: String.downcase(type)
  defp mastodon_type(_), do: "unknown"

  defp account_for_actor(actor_ap_id) when is_binary(actor_ap_id) do
    Users.get_by_ap_id(actor_ap_id) ||
      %{ap_id: actor_ap_id, nickname: fallback_username(actor_ap_id)}
  end

  defp account_for_actor(_), do: %{ap_id: "unknown", nickname: "unknown"}

  defp fallback_username(actor_ap_id) do
    case URI.parse(actor_ap_id) do
      %URI{path: path} when is_binary(path) and path != "" ->
        path
        |> String.split("/", trim: true)
        |> List.last()
        |> case do
          nil -> "unknown"
          value -> value
        end

      _ ->
        "unknown"
    end
  end

  defp format_datetime(%Object{published: %DateTime{} = dt}) do
    DateTime.to_iso8601(dt)
  end

  defp format_datetime(%Object{inserted_at: %DateTime{} = dt}) do
    DateTime.to_iso8601(dt)
  end

  defp format_datetime(%Object{inserted_at: %NaiveDateTime{} = dt}) do
    dt
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601()
  end

  defp format_datetime(_), do: DateTime.utc_now() |> DateTime.to_iso8601()
end
