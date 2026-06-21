defmodule EgregorosWeb.ViewModels.StatusTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.Activities.Note
  alias Egregoros.Interactions
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Publish
  alias Egregoros.Relationships
  alias Egregoros.Users
  alias EgregorosWeb.ViewModels.Status

  test "reaction_emojis/0 returns the default reaction set" do
    assert Status.reaction_emojis() == ["🔥", "👍", "❤️"]
  end

  test "decorates a note with actor details and counts" do
    {:ok, user} = Users.create_local_user("alice")
    {:ok, note} = Pipeline.ingest(Note.build(user, "Hello world"), local: true)

    entry = Status.decorate(note, user)

    assert entry.object.id == note.id
    assert entry.actor.handle == "@alice"
    assert entry.likes_count == 0
    assert entry.reposts_count == 0
    assert entry.reactions["🔥"].count == 0
  end

  test "includes emoji reactions outside the default set when present" do
    {:ok, user} = Users.create_local_user("alice")
    {:ok, note} = Pipeline.ingest(Note.build(user, "Hello world"), local: true)

    assert {:ok, _} = Interactions.toggle_reaction(user, note.id, "😀")

    entry = Status.decorate(note, user)

    assert entry.reactions["😀"].count == 1
    assert entry.reactions["😀"].reacted?
  end

  test "filters unsafe attachment URLs" do
    {:ok, user} = Users.create_local_user("alice")
    public = "https://www.w3.org/ns/activitystreams#Public"

    note_id = "http://localhost:4000/objects/" <> Ecto.UUID.generate()

    assert {:ok, note} =
             Objects.create_object(%{
               ap_id: note_id,
               type: "Note",
               actor: user.ap_id,
               object: nil,
               local: true,
               data: %{
                 "id" => note_id,
                 "type" => "Note",
                 "actor" => user.ap_id,
                 "to" => [public],
                 "cc" => [],
                 "content" => "<p>Hello</p>",
                 "attachment" => [
                   %{
                     "id" => "http://evil.example/media/1",
                     "type" => "Image",
                     "mediaType" => "image/png",
                     "url" => [
                       %{
                         "type" => "Link",
                         "mediaType" => "image/png",
                         "href" => "http://127.0.0.1/evil.png"
                       }
                     ],
                     "name" => "evil"
                   }
                 ]
               }
             })

    entry = Status.decorate(note, user)
    assert entry.attachments == []
  end

  test "decorates safe attachments with href, preview, and media type" do
    uniq = System.unique_integer([:positive])
    {:ok, user} = Users.create_local_user("status-attachments-#{uniq}")
    public = "https://www.w3.org/ns/activitystreams#Public"

    note_id = "http://localhost:4000/objects/" <> Ecto.UUID.generate()

    assert {:ok, note} =
             Objects.create_object(%{
               ap_id: note_id,
               type: "Note",
               actor: user.ap_id,
               object: nil,
               local: true,
               data: %{
                 "id" => note_id,
                 "type" => "Note",
                 "actor" => user.ap_id,
                 "to" => [public],
                 "cc" => [],
                 "content" => "<p>Hello</p>",
                 "attachment" => [
                   %{
                     "type" => "Image",
                     "url" => [
                       %{
                         "type" => "Link",
                         "mediaType" => "image/png",
                         "href" => "https://cdn.example/ok.png"
                       }
                     ],
                     "icon" => %{
                       "url" => [
                         %{
                           "type" => "Link",
                           "href" => "https://cdn.example/ok_thumb.png"
                         }
                       ]
                     },
                     "name" => "  ok  "
                   }
                 ]
               }
             })

    entry = Status.decorate(note, user)

    assert [
             %{
               href: "https://cdn.example/ok.png",
               preview_href: "https://cdn.example/ok_thumb.png",
               media_type: "image/png",
               description: "ok"
             }
           ] = entry.attachments
  end

  test "decorates interaction counts and flags for the current user" do
    uniq = System.unique_integer([:positive])
    {:ok, author} = Users.create_local_user("status-author-#{uniq}")
    {:ok, viewer} = Users.create_local_user("status-viewer-#{uniq}")
    {:ok, note} = Pipeline.ingest(Note.build(author, "Hello world"), local: true)

    assert {:ok, _} = Interactions.toggle_like(viewer, note.id)
    assert {:ok, _} = Interactions.toggle_repost(viewer, note.id)
    assert {:ok, :bookmarked} = Interactions.toggle_bookmark(viewer, note.id)
    assert {:ok, _} = Interactions.toggle_reaction(viewer, note.id, "🤖")

    entry = Status.decorate(note, viewer)

    assert entry.likes_count == 1
    assert entry.liked?
    assert entry.reposts_count == 1
    assert entry.reposted?
    assert entry.bookmarked?
    assert entry.reactions["🤖"].count == 1
    assert entry.reactions["🤖"].reacted?
  end

  test "decorates verifiable credentials with badge metadata" do
    uniq = System.unique_integer([:positive])
    {:ok, issuer} = Users.create_local_user("badge-issuer-#{uniq}")
    {:ok, recipient} = Users.create_local_user("badge-recipient-#{uniq}")
    {:ok, viewer} = Users.create_local_user("badge-viewer-#{uniq}")

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    valid_from = DateTime.add(now, -3600, :second)
    valid_until = DateTime.add(now, 86_400, :second)
    credential_ap_id = EgregorosWeb.Endpoint.url() <> "/objects/" <> Ecto.UUID.generate()

    {:ok, credential} =
      Objects.create_object(%{
        ap_id: credential_ap_id,
        type: "VerifiableCredential",
        actor: issuer.ap_id,
        object: nil,
        local: true,
        data: %{
          "id" => credential_ap_id,
          "type" => ["VerifiableCredential", "OpenBadgeCredential"],
          "issuer" => issuer.ap_id,
          "to" => ["https://www.w3.org/ns/activitystreams#Public"],
          "validFrom" => DateTime.to_iso8601(valid_from),
          "validUntil" => DateTime.to_iso8601(valid_until),
          "credentialSubject" => %{
            "id" => recipient.ap_id,
            "type" => "AchievementSubject",
            "achievement" => %{
              "id" => "https://example.com/badges/donator",
              "type" => "Achievement",
              "name" => "Donator",
              "description" => "Awarded for supporting the instance.",
              "image" => %{
                "id" => "https://cdn.example/badges/donator.png",
                "type" => "Image"
              }
            }
          }
        }
      })

    entry = Status.decorate(credential, viewer)

    assert entry.object.ap_id == credential_ap_id
    assert entry.object.type == "VerifiableCredential"
    assert entry.badge.title == "Donator"
    assert entry.badge.description == "Awarded for supporting the instance."
    assert entry.badge.image_url == "https://cdn.example/badges/donator.png"
    assert entry.badge.validity == "Valid"
    assert is_binary(entry.badge.valid_range)
    assert entry.badge.recipient.handle == "@#{recipient.nickname}"
  end

  test "badge view model resolves issuer ids from issuer objects and did:web identifiers" do
    uniq = System.unique_integer([:positive])
    {:ok, issuer} = Users.create_local_user("badge-issuer-object-#{uniq}")
    {:ok, recipient} = Users.create_local_user("badge-recipient-object-#{uniq}")
    {:ok, viewer} = Users.create_local_user("badge-viewer-object-#{uniq}")

    credential_ap_id = EgregorosWeb.Endpoint.url() <> "/objects/" <> Ecto.UUID.generate()

    {:ok, credential} =
      Objects.create_object(%{
        ap_id: credential_ap_id,
        type: "VerifiableCredential",
        actor: issuer.ap_id,
        object: nil,
        local: true,
        data: %{
          "id" => credential_ap_id,
          "type" => ["VerifiableCredential", "OpenBadgeCredential"],
          "issuer" => %{"id" => issuer.ap_id},
          "to" => ["https://www.w3.org/ns/activitystreams#Public"],
          "credentialSubject" => %{
            "id" => recipient.ap_id,
            "type" => "AchievementSubject",
            "achievement" => %{
              "id" => "https://example.com/badges/donator",
              "type" => "Achievement",
              "name" => "Donator",
              "image" => %{"id" => "/badges/donator.png", "type" => "Image"}
            }
          }
        }
      })

    entry = Status.decorate(credential, viewer)
    assert entry.badge.issuer_ap_id == issuer.ap_id

    did_credential_ap_id = EgregorosWeb.Endpoint.url() <> "/objects/" <> Ecto.UUID.generate()

    {:ok, did_credential} =
      Objects.create_object(%{
        ap_id: did_credential_ap_id,
        type: "VerifiableCredential",
        actor: issuer.ap_id,
        object: nil,
        local: true,
        data: %{
          "id" => did_credential_ap_id,
          "type" => ["VerifiableCredential", "OpenBadgeCredential"],
          "issuer" => "did:web:remote.example",
          "to" => ["https://www.w3.org/ns/activitystreams#Public"],
          "credentialSubject" => %{
            "id" => recipient.ap_id,
            "type" => "AchievementSubject",
            "achievement" => %{
              "id" => "https://example.com/badges/donator2",
              "type" => "Achievement",
              "name" => "Donator2",
              "image" => %{"id" => "/badges/donator2.png", "type" => "Image"}
            }
          }
        }
      })

    did_entry = Status.decorate(did_credential, viewer)
    assert did_entry.badge.issuer_ap_id == "https://remote.example"
    assert did_entry.badge.image_url == "https://remote.example/badges/donator2.png"
  end

  test "decorates announces of verifiable credentials" do
    uniq = System.unique_integer([:positive])
    {:ok, issuer} = Users.create_local_user("badge-announce-issuer-#{uniq}")
    {:ok, recipient} = Users.create_local_user("badge-announce-recipient-#{uniq}")
    {:ok, reposter} = Users.create_local_user("badge-announce-reposter-#{uniq}")

    credential_ap_id = EgregorosWeb.Endpoint.url() <> "/objects/" <> Ecto.UUID.generate()

    {:ok, credential} =
      Objects.create_object(%{
        ap_id: credential_ap_id,
        type: "VerifiableCredential",
        actor: issuer.ap_id,
        object: nil,
        local: true,
        data: %{
          "id" => credential_ap_id,
          "type" => ["VerifiableCredential", "OpenBadgeCredential"],
          "issuer" => issuer.ap_id,
          "to" => ["https://www.w3.org/ns/activitystreams#Public"],
          "validFrom" =>
            DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
          "credentialSubject" => %{
            "id" => recipient.ap_id,
            "type" => "AchievementSubject",
            "achievement" => %{
              "id" => "https://example.com/badges/founder",
              "type" => "Achievement",
              "name" => "Founder",
              "description" => "Issued for founding support."
            }
          }
        }
      })

    announce_ap_id = EgregorosWeb.Endpoint.url() <> "/objects/" <> Ecto.UUID.generate()

    {:ok, announce} =
      Objects.create_object(%{
        ap_id: announce_ap_id,
        type: "Announce",
        actor: reposter.ap_id,
        object: credential.ap_id,
        local: true,
        data: %{
          "id" => announce_ap_id,
          "type" => "Announce",
          "actor" => reposter.ap_id,
          "object" => credential.ap_id
        }
      })

    reposter_ap_id = reposter.ap_id

    assert [
             %{
               feed_id: announce_db_id,
               object: %{ap_id: ^credential_ap_id},
               reposted_by: %{ap_id: ^reposter_ap_id},
               badge: %{title: "Founder"}
             }
           ] = Status.decorate_many([announce], reposter)

    assert announce_db_id == announce.id
  end

  test "decorates polls with a poll view model" do
    {:ok, author} = Users.create_local_user("status-poll-author")
    {:ok, viewer} = Users.create_local_user("status-poll-viewer")

    question = %{
      "id" => EgregorosWeb.Endpoint.url() <> "/objects/" <> Ecto.UUID.generate(),
      "type" => "Question",
      "attributedTo" => author.ap_id,
      "context" => EgregorosWeb.Endpoint.url() <> "/contexts/" <> Ecto.UUID.generate(),
      "to" => ["https://www.w3.org/ns/activitystreams#Public"],
      "content" => "Pick one",
      "published" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "oneOf" => [
        %{"name" => "Red", "replies" => %{"totalItems" => 5}},
        %{"name" => "Blue", "replies" => %{"totalItems" => 3}}
      ],
      "closed" => DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.to_iso8601()
    }

    {:ok, poll} = Pipeline.ingest(question, local: true)

    entry = Status.decorate(poll, viewer)

    assert entry.object.type == "Question"
    assert entry.poll.multiple? == false
    assert entry.poll.options == [%{name: "Red", votes: 5}, %{name: "Blue", votes: 3}]
    assert entry.poll.total_votes == 8
    assert entry.poll.voters_count == 0
    assert entry.poll.expired? == false
    assert entry.poll.own_poll? == false
    assert entry.poll.voted? == false
    assert %DateTime{} = entry.poll.closed
  end

  test "marks polls as voted for users in the voters list" do
    {:ok, author} = Users.create_local_user("status-poll-voted-author")
    {:ok, voter} = Users.create_local_user("status-poll-voted-user")

    question = %{
      "id" => EgregorosWeb.Endpoint.url() <> "/objects/" <> Ecto.UUID.generate(),
      "type" => "Question",
      "attributedTo" => author.ap_id,
      "context" => EgregorosWeb.Endpoint.url() <> "/contexts/" <> Ecto.UUID.generate(),
      "to" => ["https://www.w3.org/ns/activitystreams#Public"],
      "content" => "Pick one",
      "published" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "oneOf" => [
        %{"name" => "Yes", "replies" => %{"totalItems" => 0}},
        %{"name" => "No", "replies" => %{"totalItems" => 0}}
      ],
      "closed" => DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.to_iso8601()
    }

    {:ok, poll} = Pipeline.ingest(question, local: true)

    assert {:ok, _updated} = Publish.vote_on_poll(voter, poll, [0])

    poll = Objects.get_by_ap_id(poll.ap_id)
    entry = Status.decorate(poll, voter)

    assert entry.poll.voted? == true
    assert entry.poll.voters_count == 1
    assert entry.poll.total_votes == 1
  end

  test "marks anyOf polls as multiple choice" do
    {:ok, author} = Users.create_local_user("status-poll-anyof-author")
    {:ok, viewer} = Users.create_local_user("status-poll-anyof-viewer")

    question = %{
      "id" => EgregorosWeb.Endpoint.url() <> "/objects/" <> Ecto.UUID.generate(),
      "type" => "Question",
      "attributedTo" => author.ap_id,
      "context" => EgregorosWeb.Endpoint.url() <> "/contexts/" <> Ecto.UUID.generate(),
      "to" => ["https://www.w3.org/ns/activitystreams#Public"],
      "content" => "Pick any",
      "published" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "anyOf" => [
        %{"name" => "A", "replies" => %{"totalItems" => 0}},
        %{"name" => "B", "replies" => %{"totalItems" => 0}}
      ],
      "closed" => DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.to_iso8601()
    }

    {:ok, poll} = Pipeline.ingest(question, local: true)

    entry = Status.decorate(poll, viewer)
    assert entry.poll.multiple? == true
  end

  test "includes reblogs of posts addressed to the viewer" do
    uniq = System.unique_integer([:positive])
    {:ok, author} = Users.create_local_user("status-direct-author-#{uniq}")
    {:ok, reposter} = Users.create_local_user("status-direct-reposter-#{uniq}")
    {:ok, viewer} = Users.create_local_user("status-direct-viewer-#{uniq}")

    note_id = "http://localhost:4000/objects/" <> Ecto.UUID.generate()

    assert {:ok, note} =
             Objects.create_object(%{
               ap_id: note_id,
               type: "Note",
               actor: author.ap_id,
               object: nil,
               local: true,
               data: %{
                 "id" => note_id,
                 "type" => "Note",
                 "actor" => author.ap_id,
                 "to" => [%{"id" => viewer.ap_id}],
                 "content" => "hi"
               }
             })

    announce_id = "http://localhost:4000/objects/" <> Ecto.UUID.generate()

    assert {:ok, announce} =
             Objects.create_object(%{
               ap_id: announce_id,
               type: "Announce",
               actor: reposter.ap_id,
               object: note.ap_id,
               local: true,
               data: %{
                 "id" => announce_id,
                 "type" => "Announce",
                 "actor" => reposter.ap_id,
                 "object" => note.ap_id
               }
             })

    reposter_ap_id = reposter.ap_id

    assert [
             %{
               feed_id: announce_db_id,
               object: %{ap_id: ^note_id},
               reposted_by: %{ap_id: ^reposter_ap_id}
             }
           ] = Status.decorate_many([announce], viewer)

    assert announce_db_id == announce.id
  end

  test "filters reblogs of followers-only posts unless the viewer follows the author" do
    uniq = System.unique_integer([:positive])
    {:ok, author} = Users.create_local_user("status-followers-author-#{uniq}")
    {:ok, reposter} = Users.create_local_user("status-followers-reposter-#{uniq}")
    {:ok, viewer} = Users.create_local_user("status-followers-viewer-#{uniq}")

    note_id = "http://localhost:4000/objects/" <> Ecto.UUID.generate()

    {:ok, note} =
      Objects.create_object(%{
        ap_id: note_id,
        type: "Note",
        actor: author.ap_id,
        object: nil,
        local: true,
        data: %{
          "id" => note_id,
          "type" => "Note",
          "actor" => author.ap_id,
          "to" => [author.ap_id <> "/followers"],
          "content" => "followers-only"
        }
      })

    announce_id = "http://localhost:4000/objects/" <> Ecto.UUID.generate()

    {:ok, announce} =
      Objects.create_object(%{
        ap_id: announce_id,
        type: "Announce",
        actor: reposter.ap_id,
        object: note.ap_id,
        local: true,
        data: %{
          "id" => announce_id,
          "type" => "Announce",
          "actor" => reposter.ap_id,
          "object" => note.ap_id
        }
      })

    assert Status.decorate_many([announce], viewer) == []

    assert {:ok, _follow} =
             Pipeline.ingest(
               %{
                 "id" => "https://local.example/activities/follow/#{uniq}",
                 "type" => "Follow",
                 "actor" => viewer.ap_id,
                 "object" => author.ap_id
               },
               local: true
             )

    reposter_ap_id = reposter.ap_id

    assert [
             %{
               feed_id: announce_db_id,
               object: %{ap_id: ^note_id},
               reposted_by: %{ap_id: ^reposter_ap_id}
             }
           ] = Status.decorate_many([announce], viewer)

    assert announce_db_id == announce.id
    assert reposter_ap_id == reposter.ap_id
  end

  test "filters reblogs when the announced object is missing" do
    uniq = System.unique_integer([:positive])
    {:ok, reposter} = Users.create_local_user("status-missing-reposter-#{uniq}")

    announce_id = "http://localhost:4000/objects/" <> Ecto.UUID.generate()

    assert {:ok, announce} =
             Objects.create_object(%{
               ap_id: announce_id,
               type: "Announce",
               actor: reposter.ap_id,
               object: "https://missing.example/objects/#{uniq}",
               local: true,
               data: %{
                 "id" => announce_id,
                 "type" => "Announce",
                 "actor" => reposter.ap_id,
                 "object" => "https://missing.example/objects/#{uniq}"
               }
             })

    assert Status.decorate_many([announce], reposter) == []
  end

  test "decorates unknown object maps with a feed_id and default reactions" do
    entry = Status.decorate(%{"id" => "https://example.com/objects/1", "actor" => nil}, nil)

    assert entry.feed_id == "https://example.com/objects/1"
    assert entry.likes_count == 0
    assert entry.reactions["🔥"].count == 0
  end

  test "returns nil for announces with blank object ids" do
    assert Status.decorate(%{type: "Announce", object: " "}, nil) == nil
  end

  test "decorates unknown object maps with emoji reaction counts when ap_id is present" do
    uniq = System.unique_integer([:positive])
    {:ok, user} = Users.create_local_user("status-unknown-reactions-#{uniq}")
    object_ap_id = "https://example.com/objects/#{uniq}"

    assert {:ok, _reaction} =
             Relationships.upsert_relationship(%{
               type: "EmojiReact:😀",
               actor: user.ap_id,
               object: object_ap_id,
               emoji_url: "https://cdn.example/emoji.png"
             })

    entry =
      Status.decorate(%{id: uniq, type: "Mystery", ap_id: object_ap_id, actor: user.ap_id}, user)

    assert entry.reactions["😀"].count == 1
    assert entry.reactions["😀"].reacted?
  end

  test "merges emoji reaction counts for the same emoji across urls" do
    uniq = System.unique_integer([:positive])
    {:ok, author} = Users.create_local_user("status-emoji-counts-author-#{uniq}")
    {:ok, note} = Pipeline.ingest(Note.build(author, "Hello world"), local: true)
    {:ok, reactor1} = Users.create_local_user("status-emoji-reactor1-#{uniq}")
    {:ok, reactor2} = Users.create_local_user("status-emoji-reactor2-#{uniq}")

    assert {:ok, _reaction} =
             Relationships.upsert_relationship(%{
               type: "EmojiReact:😀",
               actor: reactor1.ap_id,
               object: note.ap_id,
               activity_ap_id: "https://local.example/reactions/#{uniq}-1",
               emoji_url: nil
             })

    assert {:ok, _reaction} =
             Relationships.upsert_relationship(%{
               type: "EmojiReact:😀",
               actor: reactor2.ap_id,
               object: note.ap_id,
               activity_ap_id: "https://local.example/reactions/#{uniq}-2",
               emoji_url: "https://cdn.example/emoji.png"
             })

    entry = Status.decorate(note, nil)

    assert entry.reactions["😀"].count == 2
    refute entry.reactions["😀"].reacted?
  end

  test "decorate_many supports current_user as an ap_id string for reblogs" do
    uniq = System.unique_integer([:positive])
    {:ok, author} = Users.create_local_user("status-string-author-#{uniq}")
    {:ok, reposter} = Users.create_local_user("status-string-reposter-#{uniq}")
    {:ok, viewer} = Users.create_local_user("status-string-viewer-#{uniq}")
    public = "https://www.w3.org/ns/activitystreams#Public"

    note_id = "http://localhost:4000/objects/" <> Ecto.UUID.generate()

    {:ok, note} =
      Objects.create_object(%{
        ap_id: note_id,
        type: "Note",
        actor: author.ap_id,
        object: nil,
        local: true,
        data: %{
          "id" => note_id,
          "type" => "Note",
          "actor" => author.ap_id,
          "to" => [public],
          "cc" => [],
          "content" => "hi"
        }
      })

    announce_id = "http://localhost:4000/objects/" <> Ecto.UUID.generate()

    {:ok, announce} =
      Objects.create_object(%{
        ap_id: announce_id,
        type: "Announce",
        actor: reposter.ap_id,
        object: note.ap_id,
        local: true,
        data: %{
          "id" => announce_id,
          "type" => "Announce",
          "actor" => reposter.ap_id,
          "object" => note.ap_id
        }
      })

    reposter_ap_id = reposter.ap_id

    assert [
             %{
               feed_id: announce_db_id,
               object: %{ap_id: ^note_id},
               reposted_by: %{ap_id: ^reposter_ap_id}
             }
           ] = Status.decorate_many([announce], viewer.ap_id)

    assert announce_db_id == announce.id
  end

  test "badge validity labels and ranges reflect not yet valid and expired credentials" do
    uniq = System.unique_integer([:positive])
    {:ok, issuer} = Users.create_local_user("badge-validity-issuer-#{uniq}")
    {:ok, recipient} = Users.create_local_user("badge-validity-recipient-#{uniq}")

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    future = DateTime.add(now, 3600, :second)
    past = DateTime.add(now, -3600, :second)

    future_ap_id = EgregorosWeb.Endpoint.url() <> "/objects/" <> Ecto.UUID.generate()

    {:ok, future_credential} =
      Objects.create_object(%{
        ap_id: future_ap_id,
        type: "VerifiableCredential",
        actor: issuer.ap_id,
        object: nil,
        local: true,
        data: %{
          "id" => future_ap_id,
          "type" => ["VerifiableCredential", "OpenBadgeCredential"],
          "issuer" => issuer.ap_id,
          "to" => ["https://www.w3.org/ns/activitystreams#Public"],
          "validFrom" => DateTime.to_iso8601(future),
          "credentialSubject" => %{
            "id" => recipient.ap_id,
            "type" => "AchievementSubject",
            "achievement" => %{
              "id" => "https://example.com/badges/future",
              "type" => "Achievement",
              "name" => "Future Badge"
            }
          }
        }
      })

    future_entry = Status.decorate(future_credential, recipient)

    assert future_entry.badge.validity == "Not yet valid"
    assert is_binary(future_entry.badge.valid_range)
    assert String.starts_with?(future_entry.badge.valid_range, "Valid from ")

    expired_ap_id = EgregorosWeb.Endpoint.url() <> "/objects/" <> Ecto.UUID.generate()

    {:ok, expired_credential} =
      Objects.create_object(%{
        ap_id: expired_ap_id,
        type: "VerifiableCredential",
        actor: issuer.ap_id,
        object: nil,
        local: true,
        data: %{
          "id" => expired_ap_id,
          "type" => ["VerifiableCredential", "OpenBadgeCredential"],
          "issuer" => issuer.ap_id,
          "to" => ["https://www.w3.org/ns/activitystreams#Public"],
          "validUntil" => DateTime.to_iso8601(past),
          "credentialSubject" => %{
            "id" => recipient.ap_id,
            "type" => "AchievementSubject",
            "achievement" => %{
              "id" => "https://example.com/badges/expired",
              "type" => "Achievement",
              "name" => "Expired Badge",
              "image" => %{
                "url" => "https://cdn.example/badges/expired.jpg",
                "type" => "Image"
              }
            }
          }
        }
      })

    expired_entry = Status.decorate(expired_credential, recipient)

    assert expired_entry.badge.validity == "Expired"
    assert is_binary(expired_entry.badge.valid_range)
    assert String.starts_with?(expired_entry.badge.valid_range, "Valid until ")
    assert expired_entry.badge.image_url == "https://cdn.example/badges/expired.jpg"
  end

  test "badge view models handle credentials without recipient ids" do
    uniq = System.unique_integer([:positive])
    {:ok, issuer} = Users.create_local_user("badge-no-recipient-issuer-#{uniq}")

    credential_ap_id = EgregorosWeb.Endpoint.url() <> "/objects/" <> Ecto.UUID.generate()

    {:ok, credential} =
      Objects.create_object(%{
        ap_id: credential_ap_id,
        type: "VerifiableCredential",
        actor: issuer.ap_id,
        object: nil,
        local: true,
        data: %{
          "id" => credential_ap_id,
          "type" => ["VerifiableCredential", "OpenBadgeCredential"],
          "issuer" => issuer.ap_id,
          "to" => ["https://www.w3.org/ns/activitystreams#Public"],
          "credentialSubject" => %{
            "type" => "AchievementSubject",
            "achievement" => %{
              "id" => "https://example.com/badges/norecipient",
              "type" => "Achievement",
              "name" => "No Recipient Badge"
            }
          }
        }
      })

    entry = Status.decorate(credential, nil)

    assert entry.badge.recipient == nil
    assert entry.badge.badge_path == nil
    assert entry.badge.valid_range == nil
  end
end
