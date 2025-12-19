defmodule PleromaRedux.HTTP.Stub do
  @behaviour PleromaRedux.HTTP

  @impl true
  def get(_url, _headers) do
    {:ok, %{status: 200, body: %{}, headers: []}}
  end

  @impl true
  def post(_url, _body, _headers) do
    {:ok, %{status: 202, body: "", headers: []}}
  end
end

