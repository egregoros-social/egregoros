defmodule PleromaRedux.Users do
  import Ecto.Query, only: [from: 2]

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
      %User{} = user ->
        {:ok, user}

      nil ->
        case create_local_user(nickname) do
          {:ok, %User{} = user} ->
            {:ok, user}

          {:error, %Ecto.Changeset{} = changeset} ->
            if local_user_unique_conflict?(changeset) do
              case get_by_nickname(nickname) do
                %User{} = user -> {:ok, user}
                nil -> {:error, changeset}
              end
            else
              {:error, changeset}
            end
        end
    end
  end

  defp local_user_unique_conflict?(%Ecto.Changeset{} = changeset) do
    Enum.any?(changeset.errors, fn
      {:nickname, {_msg, opts}} -> Keyword.get(opts, :constraint) == :unique
      {:ap_id, {_msg, opts}} -> Keyword.get(opts, :constraint) == :unique
      _ -> false
    end)
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

  def get_by_nickname(nickname) when is_binary(nickname) do
    nickname = String.trim(nickname)
    Repo.get_by(User, nickname: nickname, local: true)
  end

  def get_by_nickname(_nickname), do: nil

  def get_by_nickname_and_domain(nickname, domain)
      when is_binary(nickname) and is_binary(domain) do
    nickname = String.trim(nickname)
    domain = String.trim(domain)

    Repo.get_by(User, nickname: nickname, domain: domain, local: false)
  end

  def get_by_nickname_and_domain(_nickname, _domain), do: nil

  def get_by_handle(handle) when is_binary(handle) do
    handle =
      handle
      |> String.trim()
      |> String.trim_leading("@")

    case String.split(handle, "@", parts: 2) do
      [nickname] when nickname != "" ->
        get_by_nickname(nickname)

      [nickname, domain] when nickname != "" and domain != "" ->
        get_by_nickname_and_domain(nickname, domain)

      _ ->
        nil
    end
  end

  def get_by_handle(_handle), do: nil

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

  def search(query, opts \\ []) when is_binary(query) and is_list(opts) do
    query = String.trim(query)
    limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()

    if query == "" do
      []
    else
      pattern = "%" <> query <> "%"

      from(u in User,
        where: ilike(u.nickname, ^pattern) or ilike(u.name, ^pattern),
        order_by: [asc: u.nickname],
        limit: ^limit
      )
      |> Repo.all()
    end
  end

  defp normalize_limit(limit) when is_integer(limit) do
    limit
    |> max(1)
    |> min(40)
  end

  defp normalize_limit(_), do: 20
end
