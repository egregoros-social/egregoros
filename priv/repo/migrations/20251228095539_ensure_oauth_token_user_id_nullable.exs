defmodule Egregoros.Repo.Migrations.EnsureOauthTokenUserIdNullable do
  use Ecto.Migration

  def up do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'oauth_tokens'
          AND column_name = 'user_id'
          AND is_nullable = 'NO'
      ) THEN
        ALTER TABLE oauth_tokens ALTER COLUMN user_id DROP NOT NULL;
      END IF;
    END $$;
    """)
  end

  def down do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'oauth_tokens'
          AND column_name = 'user_id'
          AND is_nullable = 'YES'
      ) AND NOT EXISTS (
        SELECT 1 FROM oauth_tokens WHERE user_id IS NULL
      ) THEN
        ALTER TABLE oauth_tokens ALTER COLUMN user_id SET NOT NULL;
      END IF;
    END $$;
    """)
  end
end
