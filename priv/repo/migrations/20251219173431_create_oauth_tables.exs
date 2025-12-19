defmodule PleromaRedux.Repo.Migrations.CreateOauthTables do
  use Ecto.Migration

  def change do
    create table(:oauth_applications) do
      add :name, :string, null: false
      add :website, :string
      add :redirect_uris, {:array, :string}, null: false, default: []
      add :scopes, :string, null: false, default: ""
      add :client_id, :string, null: false
      add :client_secret, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:oauth_applications, [:client_id])

    create table(:oauth_authorization_codes) do
      add :code, :string, null: false
      add :redirect_uri, :string, null: false
      add :scopes, :string, null: false, default: ""
      add :expires_at, :utc_datetime_usec, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :application_id, references(:oauth_applications, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:oauth_authorization_codes, [:code])
    create index(:oauth_authorization_codes, [:user_id])
    create index(:oauth_authorization_codes, [:application_id])

    create table(:oauth_tokens) do
      add :token, :string, null: false
      add :scopes, :string, null: false, default: ""
      add :revoked_at, :utc_datetime_usec
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :application_id, references(:oauth_applications, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:oauth_tokens, [:token])
    create index(:oauth_tokens, [:user_id])
    create index(:oauth_tokens, [:application_id])
  end
end
