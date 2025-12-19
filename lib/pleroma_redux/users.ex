defmodule PleromaRedux.Users do
  alias PleromaRedux.Keys
  alias PleromaRedux.Password
  alias PleromaRedux.Repo
  alias PleromaRedux.User
  alias PleromaReduxWeb.Endpoint

  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  def upsert_user(%{ap_id: ap_id} = attrs) when is_binary(ap_id) do
    case get_by_ap_id(ap_id) do
      nil ->
        create_user(attrs)

      %User{} = user ->
        user
        |> User.changeset(attrs)
        |> Repo.update()
    end
  end

  def create_local_user(nickname) when is_binary(nickname) do
    base = Endpoint.url() <> "/users/" <> nickname
    {public_key, private_key} = Keys.generate_rsa_keypair()

    create_user(%{
      nickname: nickname,
      ap_id: base,
      inbox: base <> "/inbox",
      outbox: base <> "/outbox",
      public_key: public_key,
      private_key: private_key,
      local: true
    })
  end

  def register_local_user(attrs) when is_map(attrs) do
    nickname = attrs |> Map.get(:nickname, "") |> to_string() |> String.trim()
    email = attrs |> Map.get(:email, "") |> to_string() |> String.trim()
    password = attrs |> Map.get(:password, "") |> to_string()

    cond do
      nickname == "" ->
        {:error, :invalid_nickname}

      email == "" ->
        {:error, :invalid_email}

      password == "" ->
        {:error, :invalid_password}

      String.length(password) < 8 ->
        {:error, :invalid_password}

      true ->
        base = Endpoint.url() <> "/users/" <> nickname
        {public_key, private_key} = Keys.generate_rsa_keypair()

        create_user(%{
          nickname: nickname,
          ap_id: base,
          inbox: base <> "/inbox",
          outbox: base <> "/outbox",
          public_key: public_key,
          private_key: private_key,
          local: true,
          email: email,
          password_hash: Password.hash(password),
          name: Map.get(attrs, :name),
          bio: Map.get(attrs, :bio),
          avatar_url: Map.get(attrs, :avatar_url)
        })
    end
  end

  def get_or_create_local_user(nickname) when is_binary(nickname) do
    case get_by_nickname(nickname) do
      %User{} = user -> {:ok, user}
      nil -> create_local_user(nickname)
    end
  end

  def get_by_ap_id(nil), do: nil
  def get_by_ap_id(ap_id), do: Repo.get_by(User, ap_id: ap_id)

  def get(id) when is_integer(id), do: Repo.get(User, id)

  def get(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> Repo.get(User, int)
      _ -> nil
    end
  end

  def get_by_nickname(nil), do: nil
  def get_by_nickname(nickname), do: Repo.get_by(User, nickname: nickname)

  def get_by_email(nil), do: nil

  def get_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: String.trim(email))
  end

  def authenticate_local_user(email, password)
      when is_binary(email) and is_binary(password) do
    email = String.trim(email)

    with %User{local: true, password_hash: hash} when is_binary(hash) <- get_by_email(email),
         true <- Password.verify(password, hash) do
      {:ok, get_by_email(email)}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def update_profile(%User{} = user, attrs) when is_map(attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  def update_password(%User{} = user, current_password, new_password)
      when is_binary(current_password) and is_binary(new_password) do
    cond do
      user.password_hash == nil ->
        {:error, :unauthorized}

      not Password.verify(current_password, user.password_hash) ->
        {:error, :unauthorized}

      String.length(new_password) < 8 ->
        {:error, :invalid_password}

      true ->
        user
        |> User.changeset(%{password_hash: Password.hash(new_password)})
        |> Repo.update()
    end
  end
end
