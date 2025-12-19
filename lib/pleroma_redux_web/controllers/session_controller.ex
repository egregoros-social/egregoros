defmodule PleromaReduxWeb.SessionController do
  use PleromaReduxWeb, :controller

  alias PleromaRedux.Users

  def new(conn, _params) do
    form = Phoenix.Component.to_form(%{"email" => "", "password" => ""}, as: :session)
    render(conn, :new, form: form, error: nil)
  end

  def create(conn, %{"session" => %{} = params}) do
    email = params |> Map.get("email", "") |> to_string() |> String.trim()
    password = params |> Map.get("password", "") |> to_string()

    form = Phoenix.Component.to_form(%{"email" => email, "password" => ""}, as: :session)

    case Users.authenticate_local_user(email, password) do
      {:ok, user} ->
        conn
        |> put_session(:user_id, user.id)
        |> redirect(to: ~p"/")

      {:error, _} ->
        conn
        |> put_status(:unauthorized)
        |> render(:new, form: form, error: "Invalid email or password.")
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> text("Unprocessable Entity")
  end
end

