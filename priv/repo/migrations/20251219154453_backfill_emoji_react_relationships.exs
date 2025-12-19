defmodule PleromaRedux.Repo.Migrations.BackfillEmojiReactRelationships do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO relationships (type, actor, object, activity_ap_id, inserted_at, updated_at)
    SELECT 'EmojiReact:' || emoji, actor, object, ap_id, NOW(), NOW()
    FROM (
      SELECT DISTINCT ON (actor, object, (data->>'content')) actor, object, ap_id, (data->>'content') AS emoji
      FROM objects
      WHERE type = 'EmojiReact'
        AND (data->>'content') IS NOT NULL
        AND (data->>'content') <> ''
      ORDER BY actor, object, (data->>'content'), inserted_at DESC NULLS LAST, id DESC
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
