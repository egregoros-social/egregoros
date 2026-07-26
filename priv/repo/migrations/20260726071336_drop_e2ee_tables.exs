defmodule Egregoros.Repo.Migrations.DropE2eeTables do
  use Ecto.Migration

  # End-to-end encrypted DMs were removed ahead of the Pleroma-compatibility
  # migration (see `e2ee_dm.md`). This drops the key material for good: the
  # wrapped private keys lived in `e2ee_key_wrappers`, so any ciphertext that
  # remains anywhere becomes permanently undecryptable once this runs.
  #
  # Not dropped here: rows in `objects` with `type = 'EncryptedMessage'` (or a
  # leftover `data->'egregoros:e2ee_dm'` payload). They are unreachable — the
  # DM queries only look at Note now, and status queries never included the
  # type — but they still occupy space. Operators who want them gone can run:
  #
  #   DELETE FROM objects WHERE type = 'EncryptedMessage';
  #
  # That is deliberately left as an operator decision rather than an automatic
  # data deletion.

  def up do
    drop_if_exists table(:e2ee_key_wrappers)
    drop_if_exists table(:e2ee_keys)
    drop_if_exists table(:e2ee_actor_keys)
  end

  # Deliberately irreversible. Recreating the tables would not restore the key
  # material, and the tables' real pre-drop shape included a vestigial
  # `legacy_id` column left behind by the flake-id migration, so a hand-written
  # `create table` here would quietly diverge from it. Reviving E2EE means
  # writing a fresh migration, not rolling this one back — and rolling back past
  # `20260126102530_switch_primary_keys_to_flake_ids` already raises anyway.
  def down do
    raise Ecto.MigrationError,
          "drop_e2ee_tables is irreversible: the E2EE key material is gone. " <>
            "If E2EE DMs are revived, add a new migration that creates the tables."
  end
end
