defmodule Egregoros.Repo.Migrations.ReplaceEd25519PublicKeyWithAssertionMethod do
  use Ecto.Migration

  import Ecto.Query

  alias Egregoros.Keys
  alias Egregoros.VerifiableCredentials.AssertionMethod

  def up do
    alter table(:users) do
      add :assertion_method, :map
      remove :ed25519_public_key
    end

    flush()

    repo = repo()

    from(u in "users",
      where: u.local == true and not is_nil(u.ed25519_private_key),
      select: {u.id, u.ap_id, u.ed25519_private_key}
    )
    |> repo.all()
    |> Enum.each(fn {id, ap_id, private_key} ->
      case AssertionMethod.from_ed25519_private_key(ap_id, private_key) do
        {:ok, assertion_method} ->
          from(u in "users", where: u.id == ^id)
          |> repo.update_all(set: [assertion_method: assertion_method])

        _ ->
          :ok
      end
    end)
  end

  def down do
    alter table(:users) do
      add :ed25519_public_key, :binary
      remove :assertion_method
    end

    flush()

    repo = repo()

    from(u in "users",
      where: u.local == true and not is_nil(u.ed25519_private_key),
      select: {u.id, u.ed25519_private_key}
    )
    |> repo.all()
    |> Enum.each(fn {id, private_key} ->
      case Keys.ed25519_public_key_from_private_key(private_key) do
        {:ok, public_key} ->
          from(u in "users", where: u.id == ^id)
          |> repo.update_all(set: [ed25519_public_key: public_key])

        _ ->
          :ok
      end
    end)
  end
end
