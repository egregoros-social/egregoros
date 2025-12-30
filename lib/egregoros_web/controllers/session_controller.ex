defmodule EgregorosWeb.SessionController do
  use EgregorosWeb, :controller

  alias Egregoros.Users
  alias EgregorosWeb.ReturnTo

  def new(conn, params) do
    return_to = params |> Map.get("return_to", "") |> to_string()

    form =
      Phoenix.Component.to_form(%{"nickname" => "", "password" => "", "return_to" => return_to},
        as: :session
      )

    render(conn, :new, form: form, error: nil)
  end

  def create(conn, %{"session" => %{} = params}) do
    nickname = params |> Map.get("nickname", "") |> to_string() |> String.trim()
    password = params |> Map.get("password", "") |> to_string()
    return_to = params |> Map.get("return_to", "") |> to_string()

    form =
      Phoenix.Component.to_form(
        %{"nickname" => nickname, "password" => "", "return_to" => return_to},
        as: :session
      )

    case Users.authenticate_local_user(nickname, password) do
      {:ok, user} ->
        redirect_to = ReturnTo.safe_return_to(return_to) || ~p"/"

        conn
        |> put_session(:user_id, user.id)
        |> configure_session(renew: true)
        |> redirect(to: redirect_to)

      {:error, _} ->
        conn
        |> put_status(:unauthorized)
        |> render(:new, form: form, error: "Invalid nickname or password.")
    end
  end

  def create(conn, _params) do
    conn
      |> put_status(:unprocessable_entity)
      |> text("Unprocessable Entity")
  end
end
