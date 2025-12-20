defmodule PleromaRedux.AuthZ.OAuthScopes do
  @behaviour PleromaRedux.AuthZ

  alias PleromaRedux.Auth.BearerToken
  alias PleromaRedux.OAuth
  alias PleromaRedux.OAuth.Scopes
  alias PleromaRedux.OAuth.Token

  @impl true
  def authorize(conn, required_scopes) when is_list(required_scopes) do
    case BearerToken.access_token(conn) do
      nil ->
        {:error, :unauthorized}

      token ->
        case OAuth.get_token(token) do
          %Token{} = oauth_token ->
            if Scopes.contains_all?(oauth_token.scopes, required_scopes) do
              :ok
            else
              {:error, :insufficient_scope}
            end

          _ ->
            {:error, :unauthorized}
        end
    end
  end
end

