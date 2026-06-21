defmodule Egregoros.Repo.Migrations.AddEd25519KeysToUsers do
  use Ecto.Migration

  import Ecto.Query

  def up do
    alter table(:users) do
      add :ed25519_public_key, :binary
      add :ed25519_private_key, :binary
    end

    flush()

    repo = repo()

    from(u in "users",
      where:
        u.local == true and
          (is_nil(u.ed25519_public_key) or is_nil(u.ed25519_private_key)),
      select: u.id
    )
    |> repo.all()
    |> Enum.each(fn id ->
      {public_key, private_key} = Egregoros.Keys.generate_ed25519_keypair()

      from(u in "users", where: u.id == ^id)
      |> repo.update_all(set: [ed25519_public_key: public_key, ed25519_private_key: private_key])
    end)
  end

  def down do
    alter table(:users) do
      remove :ed25519_public_key
      remove :ed25519_private_key
    end
  end
end
