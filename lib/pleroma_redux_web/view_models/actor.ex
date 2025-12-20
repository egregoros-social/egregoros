defmodule PleromaReduxWeb.ViewModels.Actor do
  @moduledoc false

  alias PleromaRedux.User
  alias PleromaRedux.Users
  alias PleromaReduxWeb.URL

  def card(nil) do
    %{
      ap_id: nil,
      display_name: "Unknown",
      handle: "@unknown",
      avatar_url: nil,
      local?: false
    }
  end

  def card(ap_id) when is_binary(ap_id) do
    case Users.get_by_ap_id(ap_id) do
      %User{} = user ->
        %{
          ap_id: user.ap_id,
          display_name: user.name || user.nickname || ap_id,
          handle: handle(user, ap_id),
          avatar_url: URL.absolute(user.avatar_url),
          local?: user.local
        }

      nil ->
        %{
          ap_id: ap_id,
          display_name: ap_id,
          handle: ap_id,
          avatar_url: nil,
          local?: false
        }
    end
  end

  def handle(%User{nickname: nickname, local: true}, _ap_id)
      when is_binary(nickname) and nickname != "" do
    "@" <> nickname
  end

  def handle(%User{nickname: nickname}, ap_id)
      when is_binary(nickname) and nickname != "" and is_binary(ap_id) do
    case URI.parse(ap_id) do
      %{host: host} when is_binary(host) and host != "" -> "@#{nickname}@#{host}"
      _ -> "@" <> nickname
    end
  end

  def handle(_user, ap_id) when is_binary(ap_id), do: ap_id
  def handle(_user, _ap_id), do: "@unknown"
end
