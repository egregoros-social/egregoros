defmodule Mix.Tasks.Egregoros.Badges.Issue do
  use Mix.Task

  @shortdoc "Issue a badge to an ActivityPub actor"

  @moduledoc """
  Issue a badge to an ActivityPub actor using the instance actor.

  Usage:

      mix egregoros.badges.issue <badge_kind> <recipient_ap_id>

  The badge kind corresponds to the `badge_type` column in `badge_definitions`.
  """

  @impl true
  def run(argv) do
    Mix.Task.run("app.start")

    case argv do
      [badge_type, recipient_ap_id] ->
        issue(badge_type, recipient_ap_id)

      _ ->
        Mix.raise("""
        invalid arguments

        Usage:
          mix egregoros.badges.issue <badge_kind> <recipient_ap_id>
        """)
    end
  end

  defp issue(badge_type, recipient_ap_id)
       when is_binary(badge_type) and is_binary(recipient_ap_id) do
    case Egregoros.Badges.issue_badge(badge_type, recipient_ap_id) do
      {:ok, %{offer: offer, credential: credential}} ->
        Mix.shell().info("issued badge:")
        Mix.shell().info("  offer: #{offer.ap_id}")
        Mix.shell().info("  credential: #{credential.ap_id}")

      {:error, reason} ->
        Mix.raise("could not issue badge: #{inspect(reason)}")
    end
  end
end
