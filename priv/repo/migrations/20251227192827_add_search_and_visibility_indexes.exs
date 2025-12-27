defmodule Egregoros.Repo.Migrations.AddSearchAndVisibilityIndexes do
  use Ecto.Migration

  def change do
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm", "DROP EXTENSION IF EXISTS pg_trgm")

    execute(
      "CREATE INDEX IF NOT EXISTS objects_note_content_trgm_index\n" <>
        "ON objects USING gin ((data->>'content') gin_trgm_ops)\n" <>
        "WHERE type = 'Note'",
      "DROP INDEX IF EXISTS objects_note_content_trgm_index"
    )

    execute(
      "CREATE INDEX IF NOT EXISTS objects_note_summary_trgm_index\n" <>
        "ON objects USING gin ((data->>'summary') gin_trgm_ops)\n" <>
        "WHERE type = 'Note'",
      "DROP INDEX IF EXISTS objects_note_summary_trgm_index"
    )

    execute(
      "CREATE INDEX IF NOT EXISTS objects_status_data_path_ops_index\n" <>
        "ON objects USING gin (data jsonb_path_ops)\n" <>
        "WHERE type IN ('Note', 'Announce')",
      "DROP INDEX IF EXISTS objects_status_data_path_ops_index"
    )
  end
end
