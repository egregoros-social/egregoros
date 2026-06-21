defmodule Mix.Tasks.Egregoros.Vc.MigrateDidIssuer do
  use Mix.Task

  @shortdoc "Migrate local VCs to did:web issuer and regenerate proofs"

  @moduledoc """
  Update locally issued verifiable credentials to use the instance did:web
  issuer and regenerate their Data Integrity proofs.

  ## Examples

      mix egregoros.vc.migrate_did_issuer
      mix egregoros.vc.migrate_did_issuer --dry-run
      mix egregoros.vc.migrate_did_issuer --limit 100

  ## Options

    * `--dry-run` - report changes without writing to the database
    * `--limit` - limit the number of credentials processed
    * `--batch-size` - stream batch size (default: 100)
  """

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [dry_run: :boolean, limit: :integer, batch_size: :integer]
      )

    case Egregoros.VerifiableCredentials.Reproof.migrate_local_credentials_to_did(opts) do
      {:ok, %{updated: updated, skipped: skipped, errors: errors}} ->
        Mix.shell().info("did issuer migration complete:")
        Mix.shell().info("  updated: #{updated}")
        Mix.shell().info("  skipped: #{skipped}")
        Mix.shell().info("  errors: #{errors}")

      {:error, reason} ->
        Mix.raise("did issuer migration failed: #{inspect(reason)}")
    end
  end
end
