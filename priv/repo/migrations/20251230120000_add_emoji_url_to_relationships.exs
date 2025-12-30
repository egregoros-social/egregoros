defmodule Egregoros.Repo.Migrations.AddEmojiUrlToRelationships do
  use Ecto.Migration

  def change do
    alter table(:relationships) do
      add :emoji_url, :string
    end
  end
end
