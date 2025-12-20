defmodule PleromaRedux.AuthZ.Stub do
  @behaviour PleromaRedux.AuthZ

  @impl true
  def authorize(_conn, _required_scopes) do
    :ok
  end
end

