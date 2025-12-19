defmodule PleromaReduxWeb.MastodonAPI.AccountRenderer do
  alias PleromaRedux.User

  def render_account(%User{} = user) do
    %{
      "id" => Integer.to_string(user.id),
      "username" => user.nickname,
      "acct" => user.nickname,
      "display_name" => user.nickname,
      "url" => user.ap_id
    }
  end

  def render_account(%{ap_id: ap_id, nickname: nickname}) do
    %{
      "id" => ap_id,
      "username" => nickname,
      "acct" => nickname,
      "display_name" => nickname,
      "url" => ap_id
    }
  end

  def render_account(_), do: %{"id" => "unknown", "username" => "unknown", "acct" => "unknown"}
end
