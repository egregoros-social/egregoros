defmodule Egregoros.Activities.VerifiableCredentialTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.Activities.VerifiableCredential
  alias Egregoros.BadgeDefinition
  alias Egregoros.Repo

  test "build_for_badge omits ActivityStreams context" do
    {:ok, badge} = insert_badge_definition("ContextBadge")

    credential =
      VerifiableCredential.build_for_badge(
        badge,
        "https://example.com/users/issuer",
        "https://example.com/users/recipient"
      )

    contexts = List.wrap(credential["@context"])

    assert "https://www.w3.org/ns/credentials/v2" in contexts
    assert "https://purl.imsglobal.org/spec/ob/v3p0/context-3.0.3.json" in contexts
    refute "https://www.w3.org/ns/activitystreams" in contexts

    assert Enum.any?(contexts, fn
             %{"to" => %{"@id" => "https://www.w3.org/ns/activitystreams#to"}} -> true
             _ -> false
           end)
  end

  defp insert_badge_definition(badge_type) do
    %BadgeDefinition{}
    |> BadgeDefinition.changeset(%{
      badge_type: badge_type,
      name: badge_type,
      description: "#{badge_type} badge",
      narrative: "Issued for #{badge_type}",
      disabled: false
    })
    |> Repo.insert()
  end
end
