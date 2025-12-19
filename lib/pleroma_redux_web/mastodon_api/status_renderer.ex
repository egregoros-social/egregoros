defmodule PleromaReduxWeb.MastodonAPI.StatusRenderer do
  alias PleromaRedux.Object
  alias PleromaRedux.User
  alias PleromaRedux.Users
  alias PleromaReduxWeb.MastodonAPI.AccountRenderer

  def render_status(%Object{} = object) do
    account = account_from_actor(object.actor)
    render_status_with_account(object, account)
  end

  def render_status(%Object{} = object, %User{} = user) do
    render_status_with_account(object, AccountRenderer.render_account(user))
  end

  def render_statuses(objects) when is_list(objects) do
    Enum.map(objects, &render_status/1)
  end

  defp render_status_with_account(object, account) do
    %{
      "id" => Integer.to_string(object.id),
      "uri" => object.ap_id,
      "content" => Map.get(object.data, "content", ""),
      "account" => account,
      "created_at" => format_datetime(object)
    }
  end

  defp account_from_actor(actor) when is_binary(actor) do
    case Users.get_by_ap_id(actor) do
      %User{} = user ->
        AccountRenderer.render_account(user)

      _ ->
        %{"id" => actor, "username" => fallback_username(actor), "acct" => fallback_username(actor)}
    end
  end

  defp account_from_actor(_), do: %{"id" => "unknown", "username" => "unknown", "acct" => "unknown"}

  defp fallback_username(actor) do
    case URI.parse(actor) do
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

  defp format_datetime(%Object{inserted_at: %NaiveDateTime{} = dt}) do
    dt
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601()
  end

  defp format_datetime(%Object{}), do: DateTime.utc_now() |> DateTime.to_iso8601()
end
