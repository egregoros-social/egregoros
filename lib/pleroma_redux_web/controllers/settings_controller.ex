defmodule PleromaReduxWeb.SettingsController do
  use PleromaReduxWeb, :controller

  alias PleromaRedux.AvatarStorage
  alias PleromaRedux.Notifications
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
              "avatar" => nil
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
          notifications_count: notifications_count(user),
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
         {:ok, avatar_url} <- maybe_store_avatar(user, params),
         {:ok, _user} <- Users.update_profile(user, profile_attrs(params, avatar_url)) do
      conn
      |> put_flash(:info, "Profile updated.")
      |> redirect(to: ~p"/settings")
    else
      nil ->
        conn
        |> redirect(to: ~p"/login")
        |> halt()

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not update profile.")
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
      |> put_flash(:info, "Email updated.")
      |> redirect(to: ~p"/settings")
    else
      nil ->
        conn
        |> redirect(to: ~p"/login")
        |> halt()

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not update email.")
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
      |> put_flash(:info, "Password updated.")
      |> redirect(to: ~p"/settings")
    else
      nil ->
        conn
        |> redirect(to: ~p"/login")
        |> halt()

      false ->
        conn
        |> put_flash(:error, "Password confirmation does not match.")
        |> put_status(:unprocessable_entity)
        |> edit(%{})

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not update password.")
        |> put_status(:unprocessable_entity)
        |> edit(%{})
    end
  end

  def update_password(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> text("Unprocessable Entity")
  end

  defp profile_attrs(params, avatar_url) when is_map(params) do
    %{}
    |> maybe_put("name", Map.get(params, "name"))
    |> maybe_put("bio", Map.get(params, "bio"))
    |> maybe_put("avatar_url", avatar_url)
  end

  defp maybe_put(attrs, _key, nil), do: attrs

  defp maybe_put(attrs, key, value) when is_binary(key) do
    Map.put(attrs, key, value)
  end

  defp maybe_store_avatar(user, %{"avatar" => %Plug.Upload{} = upload}) do
    AvatarStorage.store_avatar(user, upload)
  end

  defp maybe_store_avatar(_user, _params), do: {:ok, nil}

  defp notifications_count(%User{} = user) do
    user
    |> Notifications.list_for_user(limit: 20)
    |> length()
  end
end
