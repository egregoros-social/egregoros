defmodule PleromaReduxWeb.MastodonAPI.StatusRenderer do
  alias PleromaRedux.Object
  alias PleromaRedux.User
  alias PleromaRedux.Users

  def render_status(%Object{} = object) do
    account = account_from_actor(object.actor)
    render_status_with_account(object, account)
  end

  def render_status(%Object{} = object, %User{} = user) do
    render_status_with_account(object, account_from_user(user))
  end

  def render_statuses(objects) when is_list(objects) do
    Enum.map(objects, &render_status/1)
  end

  defp render_status_with_account(object, account) do
    %{
      "id" => object.ap_id,
      "content" => Map.get(object.data, "content", ""),
      "account" => account
    }
  end

  defp account_from_actor(actor) when is_binary(actor) do
    case Users.get_by_ap_id(actor) do
      %User{} = user -> account_from_user(user)
      _ -> %{"id" => actor, "username" => fallback_username(actor), "acct" => fallback_username(actor)}
    end
  end

  defp account_from_actor(_), do: %{"id" => "unknown", "username" => "unknown", "acct" => "unknown"}

  defp account_from_user(%User{} = user) do
    %{
      "id" => user.ap_id,
      "username" => user.nickname,
      "acct" => user.nickname
    }
  end

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
end
