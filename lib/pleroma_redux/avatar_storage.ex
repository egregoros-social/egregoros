defmodule PleromaRedux.AvatarStorage do
  @callback store_avatar(PleromaRedux.User.t(), Plug.Upload.t()) ::
              {:ok, String.t()} | {:error, term()}

  def store_avatar(user, upload) do
    impl().store_avatar(user, upload)
  end

  defp impl do
    Application.get_env(:pleroma_redux, __MODULE__, PleromaRedux.AvatarStorage.Local)
  end
end
