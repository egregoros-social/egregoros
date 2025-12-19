defmodule PleromaReduxWeb.SettingsController do
  use PleromaReduxWeb, :controller

  alias PleromaRedux.User
  alias PleromaRedux.Users

  def edit(conn, _params) do
    case conn.assigns.current_user do
      %User{} = user ->
        profile_form =
          Phoenix.Component.to_form(
            %{
              "name" => user.name || "",
              "bio" => user.bio || "",
              "avatar_url" => user.avatar_url || ""
            },
            as: :profile
          )

        password_form =
          Phoenix.Component.to_form(
            %{"current_password" => "", "password" => "", "password_confirmation" => ""},
            as: :password
          )

        render(conn, :edit,
          profile_form: profile_form,
          account_form: Phoenix.Component.to_form(%{"email" => user.email || ""}, as: :account),
          password_form: password_form,
          error: nil
        )

      _ ->
        conn
        |> redirect(to: ~p"/login")
        |> halt()
    end
  end

  def update_profile(conn, %{"profile" => %{} = params}) do
    with %User{} = user <- conn.assigns.current_user,
         {:ok, _user} <-
           Users.update_profile(user, %{
             "name" => Map.get(params, "name"),
             "bio" => Map.get(params, "bio"),
             "avatar_url" => Map.get(params, "avatar_url")
           }) do
      conn
      |> redirect(to: ~p"/settings")
    else
      nil ->
        conn
        |> redirect(to: ~p"/login")
        |> halt()

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> edit(%{})
    end
  end

  def update_profile(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> text("Unprocessable Entity")
  end

  def update_account(conn, %{"account" => %{} = params}) do
    with %User{} = user <- conn.assigns.current_user,
         {:ok, _user} <- Users.update_profile(user, %{"email" => Map.get(params, "email")}) do
      conn
      |> redirect(to: ~p"/settings")
    else
      nil ->
        conn
        |> redirect(to: ~p"/login")
        |> halt()

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> edit(%{})
    end
  end

  def update_account(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> text("Unprocessable Entity")
  end

  def update_password(conn, %{"password" => %{} = params}) do
    current_password = params |> Map.get("current_password", "") |> to_string()
    password = params |> Map.get("password", "") |> to_string()
    password_confirmation = params |> Map.get("password_confirmation", "") |> to_string()

    with %User{} = user <- conn.assigns.current_user,
         true <- password != "" and password == password_confirmation,
         {:ok, _} <- Users.update_password(user, current_password, password) do
      conn
      |> redirect(to: ~p"/settings")
    else
      nil ->
        conn
        |> redirect(to: ~p"/login")
        |> halt()

      false ->
        conn
        |> put_status(:unprocessable_entity)
        |> edit(%{})

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> edit(%{})
    end
  end

  def update_password(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> text("Unprocessable Entity")
  end
end
