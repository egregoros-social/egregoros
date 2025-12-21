defmodule PleromaRedux.BannerStorage do
  @callback store_banner(PleromaRedux.User.t(), Plug.Upload.t()) ::
              {:ok, String.t()} | {:error, term()}

  def store_banner(user, upload) do
    impl().store_banner(user, upload)
  end

  defp impl do
    Application.get_env(:pleroma_redux, __MODULE__, PleromaRedux.BannerStorage.Local)
  end
end
