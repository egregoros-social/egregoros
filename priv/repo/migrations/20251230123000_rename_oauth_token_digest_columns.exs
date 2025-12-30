defmodule Egregoros.Repo.Migrations.RenameOauthTokenDigestColumns do
  use Ecto.Migration

  def up do
    rename table(:oauth_tokens), :token, to: :token_digest
    rename table(:oauth_tokens), :refresh_token, to: :refresh_token_digest

    execute(
      "ALTER INDEX IF EXISTS oauth_tokens_token_index RENAME TO oauth_tokens_token_digest_index"
    )

    execute(
      "ALTER INDEX IF EXISTS oauth_tokens_refresh_token_index RENAME TO oauth_tokens_refresh_token_digest_index"
    )
  end

  def down do
    execute(
      "ALTER INDEX IF EXISTS oauth_tokens_token_digest_index RENAME TO oauth_tokens_token_index"
    )

    execute(
      "ALTER INDEX IF EXISTS oauth_tokens_refresh_token_digest_index RENAME TO oauth_tokens_refresh_token_index"
    )

    rename table(:oauth_tokens), :token_digest, to: :token
    rename table(:oauth_tokens), :refresh_token_digest, to: :refresh_token
  end
end

