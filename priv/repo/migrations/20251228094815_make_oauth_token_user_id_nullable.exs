defmodule Egregoros.Repo.Migrations.MakeOauthTokenUserIdNullable do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE oauth_tokens ALTER COLUMN user_id DROP NOT NULL")
  end

  def down do
    execute("ALTER TABLE oauth_tokens ALTER COLUMN user_id SET NOT NULL")
  end
end
