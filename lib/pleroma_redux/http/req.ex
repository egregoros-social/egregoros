defmodule PleromaRedux.HTTP.Req do
  @behaviour PleromaRedux.HTTP

  @default_opts [redirect: false, receive_timeout: 5_000]
  @default_req_options []

  defp req_options do
    Application.get_env(:pleroma_redux, :req_options, @default_req_options)
  end

  @impl true
  def get(url, headers) do
    case Req.get(url, [headers: headers] ++ req_options() ++ @default_opts) do
      {:ok, response} ->
        {:ok, %{status: response.status, body: response.body, headers: response.headers}}

      {:error, _} = error ->
        error
    end
  end

  @impl true
  def post(url, body, headers) do
    case Req.post(url, [body: body, headers: headers] ++ req_options() ++ @default_opts) do
      {:ok, response} ->
        {:ok, %{status: response.status, body: response.body, headers: response.headers}}

      {:error, _} = error ->
        error
    end
  end
end
