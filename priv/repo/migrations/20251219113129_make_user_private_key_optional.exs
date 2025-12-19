defmodule PleromaRedux.Repo.Migrations.MakeUserPrivateKeyOptional do
  use Ecto.Migration

  def change do
    alter table(:users) do
      modify :private_key, :text, null: true
    end
  end
end
