defmodule PleromaRedux.Repo.Migrations.BackfillFollowRelationships do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO relationships (type, actor, object, activity_ap_id, inserted_at, updated_at)
    SELECT 'Follow', actor, object, ap_id, NOW(), NOW()
    FROM (
      SELECT DISTINCT ON (actor, object) actor, object, ap_id
      FROM objects
      WHERE type = 'Follow'
      ORDER BY actor, object, inserted_at DESC NULLS LAST, id DESC
    ) latest
    ON CONFLICT (type, actor, object) DO UPDATE
      SET activity_ap_id = EXCLUDED.activity_ap_id,
          updated_at = EXCLUDED.updated_at;
    """)
  end

  def down do
    :ok
  end
end
