defmodule Mix.Tasks.Egregoros.Vc.Reproof do
  use Mix.Task

  @shortdoc "Remove ActivityStreams context from local VCs and re-sign proofs"

  @moduledoc """
  Remove the ActivityStreams JSON-LD context from locally issued verifiable
  credentials and regenerate their Data Integrity proofs.

  Usage:

      mix egregoros.vc.reproof
      mix egregoros.vc.reproof --dry-run
      mix egregoros.vc.reproof --limit 100
  """

  @impl true
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, args, _invalid} =
      OptionParser.parse(argv,
        strict: [dry_run: :boolean, limit: :integer, batch_size: :integer]
      )

    if args != [] do
      Mix.raise("""
      invalid arguments

      Usage:
        mix egregoros.vc.reproof [--dry-run] [--limit N] [--batch-size N]
      """)
    end

    case Egregoros.VerifiableCredentials.Reproof.reproof_local_credentials(opts) do
      {:ok, summary} ->
        Mix.shell().info("reproof complete:")
        Mix.shell().info("  updated: #{summary.updated}")
        Mix.shell().info("  skipped: #{summary.skipped}")
        Mix.shell().info("  errors: #{summary.errors}")

      {:error, reason} ->
        Mix.raise("reproof failed: #{inspect(reason)}")
    end
  end
end
