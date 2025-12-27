defmodule Egregoros.Repo.Migrations.AddOauthTokenLifecycleColumns do
  use Ecto.Migration

  def change do
    alter table(:oauth_tokens) do
      add :refresh_token, :string
      add :expires_at, :utc_datetime_usec
      add :refresh_expires_at, :utc_datetime_usec
    end

    create unique_index(:oauth_tokens, [:refresh_token])
    create index(:oauth_tokens, [:expires_at])
    create index(:oauth_tokens, [:refresh_expires_at])
  end
end
