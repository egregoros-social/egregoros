defmodule Egregoros.InteractionsTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.Interactions
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Relationships
  alias Egregoros.Users
  alias EgregorosWeb.Endpoint

  test "toggle_like refuses to like notes the user cannot view" do
    {:ok, user} = Users.create_local_user("alice")
    {:ok, recipient} = Users.create_local_user("bob")

    {:ok, note} =
      Pipeline.ingest(
        %{
          "id" => "https://remote.example/objects/direct-like",
          "type" => "Note",
          "actor" => "https://remote.example/users/charlie",
          "content" => "Secret DM",
          "to" => [recipient.ap_id],
          "cc" => []
        },
        local: false
      )

    assert {:error, :not_found} = Interactions.toggle_like(user, note.id)
    refute Objects.get_by_type_actor_object("Like", user.ap_id, note.ap_id)
  end

  test "toggle_repost allows verifiable credentials" do
    {:ok, issuer} = Users.create_local_user("badge_issuer")
    {:ok, recipient} = Users.create_local_user("badge_recipient")

    credential = %{
      "@context" => [
        "https://www.w3.org/ns/credentials/v2",
        "https://purl.imsglobal.org/spec/ob/v3p0/context-3.0.3.json",
        "https://www.w3.org/ns/activitystreams"
      ],
      "id" => Endpoint.url() <> "/objects/" <> Ecto.UUID.generate(),
      "type" => ["VerifiableCredential", "OpenBadgeCredential"],
      "issuer" => issuer.ap_id,
      "to" => ["https://www.w3.org/ns/activitystreams#Public"],
      "validFrom" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "credentialSubject" => %{
        "id" => recipient.ap_id,
        "type" => "AchievementSubject",
        "achievement" => %{
          "id" => Endpoint.url() <> "/badges/test",
          "type" => "Achievement",
          "name" => "Tester",
          "description" => "Issued for repost testing.",
          "criteria" => %{"narrative" => "Test badge."}
        }
      }
    }

    assert {:ok, vc_object} =
             Pipeline.ingest(credential, local: true, allow_remote_recipient: true)

    assert {:ok, _announce} = Interactions.toggle_repost(issuer, vc_object.id)

    assert Objects.get_by_type_actor_object("Announce", issuer.ap_id, vc_object.ap_id)
  end

  test "toggle_reaction allows verifiable credentials" do
    {:ok, issuer} = Users.create_local_user("badge_react_issuer")
    {:ok, recipient} = Users.create_local_user("badge_react_recipient")

    credential = %{
      "@context" => [
        "https://www.w3.org/ns/credentials/v2",
        "https://purl.imsglobal.org/spec/ob/v3p0/context-3.0.3.json",
        "https://www.w3.org/ns/activitystreams"
      ],
      "id" => Endpoint.url() <> "/objects/" <> Ecto.UUID.generate(),
      "type" => ["VerifiableCredential", "OpenBadgeCredential"],
      "issuer" => issuer.ap_id,
      "to" => ["https://www.w3.org/ns/activitystreams#Public"],
      "validFrom" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "credentialSubject" => %{
        "id" => recipient.ap_id,
        "type" => "AchievementSubject",
        "achievement" => %{
          "id" => Endpoint.url() <> "/badges/test",
          "type" => "Achievement",
          "name" => "Tester",
          "description" => "Issued for reaction testing.",
          "criteria" => %{"narrative" => "Test badge."}
        }
      }
    }

    assert {:ok, vc_object} =
             Pipeline.ingest(credential, local: true, allow_remote_recipient: true)

    assert {:ok, _reaction} = Interactions.toggle_reaction(issuer, vc_object.id, "🔥")

    assert Objects.get_emoji_react(issuer.ap_id, vc_object.ap_id, "🔥")
  end

  test "toggle_bookmark allows verifiable credentials" do
    {:ok, issuer} = Users.create_local_user("badge_bookmark_issuer")
    {:ok, recipient} = Users.create_local_user("badge_bookmark_recipient")

    credential = %{
      "@context" => [
        "https://www.w3.org/ns/credentials/v2",
        "https://purl.imsglobal.org/spec/ob/v3p0/context-3.0.3.json",
        "https://www.w3.org/ns/activitystreams"
      ],
      "id" => Endpoint.url() <> "/objects/" <> Ecto.UUID.generate(),
      "type" => ["VerifiableCredential", "OpenBadgeCredential"],
      "issuer" => issuer.ap_id,
      "to" => ["https://www.w3.org/ns/activitystreams#Public"],
      "validFrom" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "credentialSubject" => %{
        "id" => recipient.ap_id,
        "type" => "AchievementSubject",
        "achievement" => %{
          "id" => Endpoint.url() <> "/badges/test",
          "type" => "Achievement",
          "name" => "Tester",
          "description" => "Issued for bookmark testing.",
          "criteria" => %{"narrative" => "Test badge."}
        }
      }
    }

    assert {:ok, vc_object} =
             Pipeline.ingest(credential, local: true, allow_remote_recipient: true)

    assert {:ok, :bookmarked} = Interactions.toggle_bookmark(issuer, vc_object.id)

    assert Relationships.get_by_type_actor_object("Bookmark", issuer.ap_id, vc_object.ap_id)
  end
end
