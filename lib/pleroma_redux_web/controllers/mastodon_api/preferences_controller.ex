defmodule PleromaReduxWeb.MastodonAPI.PreferencesController do
  use PleromaReduxWeb, :controller

  def show(conn, _params) do
    json(conn, %{
      "posting:default:visibility" => "public",
      "posting:default:sensitive" => false,
      "posting:default:language" => nil,
      "reading:expand:media" => "default",
      "reading:expand:spoilers" => false
    })
  end
end
