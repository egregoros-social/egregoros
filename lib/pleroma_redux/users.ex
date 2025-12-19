defmodule PleromaRedux.Users do
  alias PleromaRedux.Keys
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
end
