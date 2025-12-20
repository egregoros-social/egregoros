defmodule PleromaRedux.AuthZ do
  @callback authorize(Plug.Conn.t(), [String.t()]) :: :ok | {:error, term()}

  def authorize(conn, required_scopes) when is_list(required_scopes) do
    impl().authorize(conn, required_scopes)
  end

  defp impl do
    Application.get_env(:pleroma_redux, __MODULE__, PleromaRedux.AuthZ.OAuthScopes)
  end
end

