defmodule EgregorosWeb.RegistrationController do
  use EgregorosWeb, :controller

  alias Egregoros.User
  alias Egregoros.Users
  alias EgregorosWeb.ReturnTo

  def new(conn, params) do
    return_to = params |> Map.get("return_to", "") |> to_string()

    form =
      Phoenix.Component.to_form(
        %{"nickname" => "", "email" => "", "password" => "", "return_to" => return_to},
        as: :registration
      )

    render(conn, :new, form: form, error: nil)
  end

  def create(conn, %{"registration" => %{} = params}) do
    nickname = params |> Map.get("nickname", "") |> to_string() |> String.trim()

    email =
      params
      |> Map.get("email", "")
      |> to_string()
      |> String.trim()
      |> case do
        "" -> nil
        value -> value
      end

    password = params |> Map.get("password", "") |> to_string()
    return_to = params |> Map.get("return_to", "") |> to_string()

    form =
      Phoenix.Component.to_form(
        %{
          "nickname" => nickname,
          "email" => email || "",
          "password" => "",
          "return_to" => return_to
        },
        as: :registration
      )

    cond do
      nickname == "" ->
        render(conn, :new, form: form, error: "Nickname can't be empty.")

      password == "" ->
        render(conn, :new, form: form, error: "Password can't be empty.")

      Users.get_by_nickname(nickname) ->
        render(conn, :new, form: form, error: "Nickname is already registered.")

      is_binary(email) and Users.get_by_email(email) ->
        render(conn, :new, form: form, error: "Email is already registered.")

      true ->
        case Users.register_local_user(%{nickname: nickname, email: email, password: password}) do
          {:ok, %User{} = user} ->
            redirect_to = ReturnTo.safe_return_to(return_to) || ~p"/"

            conn
            |> put_session(:user_id, user.id)
            |> configure_session(renew: true)
            |> redirect(to: redirect_to)

          {:error, :invalid_password} ->
            render(conn, :new, form: form, error: "Password is invalid.")

          {:error, _changeset} ->
            render(conn, :new, form: form, error: "Could not register.")
        end
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> text("Unprocessable Entity")
  end

  def logout(conn, _params) do
    conn
    |> clear_session()
    |> configure_session(drop: true)
    |> redirect(to: ~p"/")
  end
end
