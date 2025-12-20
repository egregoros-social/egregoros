defmodule PleromaRedux.Auth.BearerToken do
  @behaviour PleromaRedux.Auth

  import Plug.Conn, only: [get_req_header: 2]

  alias PleromaRedux.OAuth
  alias PleromaRedux.OAuth.Token
  alias PleromaRedux.User

  def access_token(conn) do
    bearer_token(conn) || access_token_param(conn)
  end

  @impl true
  def current_user(conn) do
    case access_token(conn) do
      nil ->
        {:error, :unauthorized}

      token ->
        with %Token{user: %User{} = user} <- OAuth.get_token(token) do
          {:ok, user}
        else
          _ -> {:error, :unauthorized}
        end
    end
  end

  defp bearer_token(conn) do
    conn
    |> get_req_header("authorization")
    |> List.first()
    |> to_string()
    |> String.split(" ", parts: 2)
    |> case do
      ["Bearer", token] when is_binary(token) and token != "" -> token
      _ -> nil
    end
  end

  defp access_token_param(%Plug.Conn{params: %{"access_token" => token}}) when is_binary(token) do
    String.trim(token)
  end

  defp access_token_param(_conn), do: nil
end
