defmodule EgregorosWeb.MastodonAPI.StatusRendererTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.Objects
  alias Egregoros.Relationships
  alias Egregoros.Pipeline
  alias Egregoros.Publish
  alias Egregoros.TestSupport.Fixtures
  alias Egregoros.Users
  alias EgregorosWeb.Endpoint
  alias EgregorosWeb.MastodonAPI.StatusRenderer

  test "sanitizes remote html content" do
    {:ok, object} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/1",
        type: "Note",
        actor: "https://remote.example/users/alice",
        local: false,
        data: %{
          "id" => "https://remote.example/objects/1",
          "type" => "Note",
          "actor" => "https://remote.example/users/alice",
          "content" => "<p>ok</p><script>alert(1)</script>"
        }
      })

    rendered = StatusRenderer.render_status(object)

    assert rendered["content"] =~ "<p>ok</p>"
    refute rendered["content"] =~ "<script"
  end

  test "escapes local user input while still producing HTML content" do
    {:ok, user} = Users.create_local_user("alice")

    assert {:ok, create} = Publish.post_note(user, "<script>alert(1)</script>")
    note = Objects.get_by_ap_id(create.object)

    rendered = StatusRenderer.render_status(note)

    assert rendered["content"] =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
    refute rendered["content"] =~ "<script"
  end

  test "renders mentions and hashtags from ActivityPub tag data" do
    activity = Fixtures.json!("mastodon-post-activity-hashtag.json")

    assert {:ok, create} = Pipeline.ingest(activity, local: false)
    note = Objects.get_by_ap_id(create.object)

    rendered = StatusRenderer.render_status(note)

    assert rendered["content"] =~ "href=\"#{Endpoint.url()}/@lain@localtesting.pleroma.lol\""

    assert [%{"url" => url} = mention] =
             rendered["mentions"]

    assert url == Endpoint.url() <> "/@lain@localtesting.pleroma.lol"
    assert mention["username"] == "lain"
    assert mention["acct"] == "lain@localtesting.pleroma.lol"

    assert [%{"name" => "moo", "url" => "http://mastodon.example.org/tags/moo"}] =
             rendered["tags"]
  end

  test "renders status url as a local permalink when the object is local" do
    {:ok, user} = Users.create_local_user("alice")
    uuid = Ecto.UUID.generate()
    ap_id = Endpoint.url() <> "/objects/" <> uuid

    {:ok, note} =
      Objects.create_object(%{
        ap_id: ap_id,
        type: "Note",
        actor: user.ap_id,
        local: true,
        data: %{
          "id" => ap_id,
          "type" => "Note",
          "actor" => user.ap_id,
          "content" => "hello"
        }
      })

    rendered = StatusRenderer.render_status(note, user)

    assert rendered["url"] == Endpoint.url() <> "/@alice/" <> uuid
  end

  test "renders custom emojis from ActivityPub tag data" do
    activity = Fixtures.json!("kroeg-array-less-emoji.json")

    assert {:ok, create} = Pipeline.ingest(activity, local: false)
    note = Objects.get_by_ap_id(create.object)

    rendered = StatusRenderer.render_status(note)

    assert [
             %{
               "shortcode" => "icon_e_smile",
               "url" => "https://puckipedia.com/forum/images/smilies/icon_e_smile.png",
               "static_url" => "https://puckipedia.com/forum/images/smilies/icon_e_smile.png",
               "visible_in_picker" => true
             }
           ] = rendered["emojis"]
  end

  test "renders verifiable credentials with a badge message and image" do
    {:ok, issuer} = Users.create_local_user("badge_issuer")
    {:ok, recipient} = Users.create_local_user("badge_recipient")

    badge_image = "https://cdn.example/badges/test.png"

    {:ok, credential} =
      Objects.create_object(%{
        ap_id: Endpoint.url() <> "/objects/" <> Ecto.UUID.generate(),
        type: "VerifiableCredential",
        actor: issuer.ap_id,
        local: true,
        data: %{
          "id" => Endpoint.url() <> "/objects/" <> Ecto.UUID.generate(),
          "type" => ["VerifiableCredential", "OpenBadgeCredential"],
          "issuer" => issuer.ap_id,
          "to" => ["https://www.w3.org/ns/activitystreams#Public"],
          "validFrom" => "2026-01-29T00:00:00Z",
          "credentialSubject" => %{
            "id" => recipient.ap_id,
            "type" => "AchievementSubject",
            "achievement" => %{
              "id" => Endpoint.url() <> "/badges/test",
              "type" => "Achievement",
              "name" => "Contributor",
              "description" => "Awarded for supporting the community.",
              "criteria" => %{"narrative" => "Contributed to the project."},
              "image" => %{"id" => badge_image, "type" => "Image"}
            }
          }
        }
      })

    rendered = StatusRenderer.render_status(credential, issuer)

    assert rendered["content"] =~ "badge_issuer"
    assert rendered["content"] =~ "badge_recipient"
    assert rendered["content"] =~ "Contributor"

    assert [
             %{
               "type" => "image",
               "url" => ^badge_image
             }
             | _rest
           ] = rendered["media_attachments"]
  end

  test "renders verifiable credentials without badge metadata and image" do
    {:ok, issuer} = Users.create_local_user("badge_issuer_missing_fields")

    {:ok, credential} =
      Objects.create_object(%{
        ap_id: Endpoint.url() <> "/objects/" <> Ecto.UUID.generate(),
        type: "VerifiableCredential",
        actor: issuer.ap_id,
        local: true,
        data: %{
          "id" => Endpoint.url() <> "/objects/" <> Ecto.UUID.generate(),
          "type" => ["VerifiableCredential", "OpenBadgeCredential"],
          "issuer" => %{"id" => issuer.ap_id},
          "to" => ["https://www.w3.org/ns/activitystreams#Public"],
          "credentialSubject" => %{
            "type" => "AchievementSubject",
            "achievement" => %{
              "id" => Endpoint.url() <> "/badges/test",
              "type" => "Achievement"
            }
          }
        }
      })

    rendered = StatusRenderer.render_status(credential, issuer)

    assert rendered["content"] =~ "badge_issuer_missing_fields"
    assert rendered["content"] =~ "awarded a badge"
    assert rendered["media_attachments"] == []
  end

  test "renders verifiable credentials when issuer is missing by falling back to actor" do
    {:ok, credential} =
      Objects.create_object(%{
        ap_id: Endpoint.url() <> "/objects/" <> Ecto.UUID.generate(),
        type: "VerifiableCredential",
        actor: "https://remote.example/users/issuer",
        local: false,
        data: %{
          "id" => Endpoint.url() <> "/objects/" <> Ecto.UUID.generate(),
          "type" => ["VerifiableCredential", "OpenBadgeCredential"],
          "to" => ["https://www.w3.org/ns/activitystreams#Public"],
          "credentialSubject" => %{
            "type" => "AchievementSubject",
            "achievement" => %{
              "type" => "Achievement"
            }
          }
        }
      })

    rendered = StatusRenderer.render_status(credential)

    assert rendered["content"] =~ "issuer"
    assert rendered["content"] =~ "awarded a badge"
    assert rendered["media_attachments"] == []
  end

  test "renders announces as reblogs" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    {:ok, note} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/1",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/1",
          "type" => "Note",
          "actor" => alice.ap_id,
          "content" => "hello"
        }
      })

    {:ok, announce} =
      Objects.create_object(%{
        ap_id: "https://remote.example/activities/announce/1",
        type: "Announce",
        actor: bob.ap_id,
        object: note.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/activities/announce/1",
          "type" => "Announce",
          "actor" => bob.ap_id,
          "object" => note.ap_id
        }
      })

    rendered = StatusRenderer.render_status(announce, alice)

    assert rendered["account"]["username"] == "bob"
    assert rendered["content"] == ""
    assert %{"uri" => note_ap_id} = rendered["reblog"]
    assert note_ap_id == note.ap_id
  end

  test "uses the announce id as conversation_id when announce.object is blank" do
    {:ok, alice} = Users.create_local_user("announce_conversation_alice")
    uuid = Ecto.UUID.generate()

    {:ok, announce} =
      Objects.create_object(%{
        ap_id: "https://remote.example/activities/announce/blank-object/#{uuid}",
        type: "Announce",
        actor: alice.ap_id,
        object: " ",
        local: false,
        data: %{
          "id" => "https://remote.example/activities/announce/blank-object/#{uuid}",
          "type" => "Announce",
          "actor" => alice.ap_id,
          "object" => " "
        }
      })

    rendered = StatusRenderer.render_status(announce, alice)

    assert rendered["pleroma"]["conversation_id"] == announce.id
  end

  test "computes visibility from to/cc recipients" do
    {:ok, alice} = Users.create_local_user("alice")

    public = "https://www.w3.org/ns/activitystreams#Public"
    followers = alice.ap_id <> "/followers"

    {:ok, note_public} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/public",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{"id" => "https://remote.example/objects/public", "to" => [public], "cc" => []}
      })

    {:ok, note_unlisted} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/unlisted",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/unlisted",
          "to" => [followers],
          "cc" => [public]
        }
      })

    {:ok, note_private} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/private",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{"id" => "https://remote.example/objects/private", "to" => [followers], "cc" => []}
      })

    {:ok, note_direct} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/direct",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/direct",
          "to" => ["https://remote.example/users/bob"],
          "cc" => []
        }
      })

    assert StatusRenderer.render_status(note_public)["visibility"] == "public"
    assert StatusRenderer.render_status(note_unlisted)["visibility"] == "unlisted"
    assert StatusRenderer.render_status(note_private)["visibility"] == "private"
    assert StatusRenderer.render_status(note_direct)["visibility"] == "direct"
  end

  test "renders in_reply_to_id and in_reply_to_account_id when parent is known" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    {:ok, parent} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/parent",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/parent",
          "type" => "Note",
          "actor" => alice.ap_id
        }
      })

    {:ok, child} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/child",
        type: "Note",
        actor: bob.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/child",
          "type" => "Note",
          "actor" => bob.ap_id,
          "inReplyTo" => parent.ap_id
        }
      })

    rendered = StatusRenderer.render_status(child)

    assert rendered["in_reply_to_id"] == parent.id
    assert rendered["in_reply_to_account_id"] == alice.id
  end

  test "includes pleroma.conversation_id so pleroma-fe can group threads" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    {:ok, root} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/root",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/root",
          "type" => "Note",
          "actor" => alice.ap_id,
          "content" => "root"
        }
      })

    {:ok, reply} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/reply",
        type: "Note",
        actor: bob.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/reply",
          "type" => "Note",
          "actor" => bob.ap_id,
          "content" => "reply",
          "inReplyTo" => root.ap_id
        }
      })

    assert StatusRenderer.render_status(root)["pleroma"]["conversation_id"] == root.id
    assert StatusRenderer.render_status(reply)["pleroma"]["conversation_id"] == root.id
  end

  test "renders spoiler_text and sensitive flags" do
    {:ok, alice} = Users.create_local_user("alice")

    {:ok, note} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/spoiler",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/spoiler",
          "type" => "Note",
          "actor" => alice.ap_id,
          "summary" => "cw",
          "sensitive" => "true"
        }
      })

    rendered = StatusRenderer.render_status(note)

    assert rendered["spoiler_text"] == "cw"
    assert rendered["sensitive"] == true
  end

  test "renders media attachments with absolute urls and type" do
    {:ok, alice} = Users.create_local_user("alice")

    {:ok, media_object} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/media/1",
        type: "Document",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/media/1",
          "type" => "Document",
          "meta" => %{"original" => %{"width" => 640, "height" => 480}}
        }
      })

    {:ok, note} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/with-media",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/with-media",
          "type" => "Note",
          "actor" => alice.ap_id,
          "attachment" => [
            %{
              "id" => media_object.ap_id,
              "mediaType" => "video/mp4",
              "name" => "clip",
              "blurhash" => "abc",
              "url" => [%{"href" => "/media/clip.mp4", "mediaType" => "video/mp4"}]
            }
          ]
        }
      })

    rendered = StatusRenderer.render_status(note)

    assert [
             %{
               "id" => media_id,
               "type" => "video",
               "url" => url,
               "preview_url" => preview,
               "meta" => %{"original" => %{"width" => 640, "height" => 480}},
               "description" => "clip",
               "blurhash" => "abc"
             }
           ] = rendered["media_attachments"]

    assert media_id == media_object.id
    assert url == Endpoint.url() <> "/media/clip.mp4"
    assert preview == url
  end

  test "renders media attachments when attachment id is missing" do
    {:ok, alice} = Users.create_local_user("alice")
    uuid = Ecto.UUID.generate()

    {:ok, note} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/no-id-attachment/#{uuid}",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/no-id-attachment/#{uuid}",
          "type" => "Note",
          "actor" => alice.ap_id,
          "attachment" => [
            %{
              "mediaType" => "image/png",
              "name" => "pic",
              "url" => "/media/pic.png"
            }
          ]
        }
      })

    rendered = StatusRenderer.render_status(note)

    assert [
             %{
               "id" => "unknown",
               "type" => "image",
               "url" => url,
               "preview_url" => preview,
               "description" => "pic"
             }
           ] = rendered["media_attachments"]

    assert url == Endpoint.url() <> "/media/pic.png"
    assert preview == url
  end

  test "renders media attachments with an unknown type when mime is missing" do
    {:ok, alice} = Users.create_local_user("attachment_unknown_type_alice")
    uuid = Ecto.UUID.generate()

    {:ok, note} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/unknown-type/#{uuid}",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/unknown-type/#{uuid}",
          "type" => "Note",
          "actor" => alice.ap_id,
          "attachment" => [
            %{
              "name" => "blob",
              "url" => "/media/blob.bin"
            }
          ]
        }
      })

    rendered = StatusRenderer.render_status(note)

    assert [%{"type" => "unknown", "url" => url}] = rendered["media_attachments"]
    assert url == Endpoint.url() <> "/media/blob.bin"
  end

  test "uses attachment ap_id as the Mastodon id when the media object is missing" do
    {:ok, alice} = Users.create_local_user("alice")
    uuid = Ecto.UUID.generate()
    attachment_ap_id = "https://remote.example/objects/media-missing/#{uuid}"

    {:ok, note} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/with-missing-media/#{uuid}",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/with-missing-media/#{uuid}",
          "type" => "Note",
          "actor" => alice.ap_id,
          "attachment" => [
            %{
              "id" => attachment_ap_id,
              "url" => [%{"href" => "/media/clip.mp4", "mediaType" => "video/mp4"}]
            }
          ]
        }
      })

    rendered = StatusRenderer.render_status(note)

    assert [%{"id" => media_id, "type" => "video", "url" => url}] = rendered["media_attachments"]
    assert media_id == attachment_ap_id
    assert url == Endpoint.url() <> "/media/clip.mp4"
  end

  test "filters out media attachments that do not have a usable url" do
    {:ok, alice} = Users.create_local_user("alice")
    uuid = Ecto.UUID.generate()

    {:ok, note} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/with-bad-media/#{uuid}",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/with-bad-media/#{uuid}",
          "type" => "Note",
          "actor" => alice.ap_id,
          "attachment" => [
            %{
              "id" => "https://remote.example/objects/media-without-url/#{uuid}",
              "mediaType" => "image/png"
            }
          ]
        }
      })

    rendered = StatusRenderer.render_status(note)

    assert rendered["media_attachments"] == []
  end

  test "classifies audio and unknown media attachments based on mime type" do
    {:ok, alice} = Users.create_local_user("alice")
    uuid = Ecto.UUID.generate()

    {:ok, note} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/with-audio/#{uuid}",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/with-audio/#{uuid}",
          "type" => "Note",
          "actor" => alice.ap_id,
          "attachment" => [
            %{
              "id" => "https://remote.example/objects/audio/#{uuid}",
              "mediaType" => "audio/ogg",
              "url" => "/media/clip.ogg"
            },
            %{
              "id" => "https://remote.example/objects/unknown/#{uuid}",
              "mediaType" => "application/octet-stream",
              "url" => "/media/blob.bin"
            }
          ]
        }
      })

    rendered = StatusRenderer.render_status(note)

    assert [
             %{"type" => "audio", "url" => audio_url},
             %{"type" => "unknown", "url" => unknown_url}
           ] = rendered["media_attachments"]

    assert audio_url == Endpoint.url() <> "/media/clip.ogg"
    assert unknown_url == Endpoint.url() <> "/media/blob.bin"
  end

  test "does not render a reblog when the announced object is missing" do
    {:ok, alice} = Users.create_local_user("alice")

    {:ok, announce} =
      Objects.create_object(%{
        ap_id: "https://remote.example/activities/announce/missing",
        type: "Announce",
        actor: alice.ap_id,
        object: "https://remote.example/objects/missing",
        local: false,
        data: %{
          "id" => "https://remote.example/activities/announce/missing",
          "type" => "Announce",
          "actor" => alice.ap_id,
          "object" => "https://remote.example/objects/missing",
          "to" => ["https://www.w3.org/ns/activitystreams#Public"],
          "cc" => []
        }
      })

    rendered = StatusRenderer.render_status(announce)

    assert rendered["content"] == ""
    assert rendered["reblog"] == nil
  end

  test "renders announces with a missing object field as a non-reblog status" do
    {:ok, alice} = Users.create_local_user("alice")
    uuid = Ecto.UUID.generate()

    {:ok, announce} =
      Objects.create_object(%{
        ap_id: "https://remote.example/activities/announce/no-object/#{uuid}",
        type: "Announce",
        actor: alice.ap_id,
        object: nil,
        local: false,
        data: %{
          "id" => "https://remote.example/activities/announce/no-object/#{uuid}",
          "type" => "Announce",
          "actor" => alice.ap_id,
          "object" => nil
        }
      })

    rendered = StatusRenderer.render_status(announce)

    assert rendered["content"] == ""
    assert rendered["reblog"] == nil
  end

  test "renders emoji reactions with :me when current_user reacted" do
    {:ok, alice} = Users.create_local_user("alice")

    {:ok, note} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/1",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/1",
          "type" => "Note",
          "actor" => alice.ap_id,
          "content" => "hello"
        }
      })

    {:ok, _rel} =
      Relationships.upsert_relationship(%{
        type: "EmojiReact:🔥",
        actor: alice.ap_id,
        object: note.ap_id,
        activity_ap_id: "https://remote.example/activities/react/1"
      })

    rendered = StatusRenderer.render_status(note, alice)

    assert [%{"name" => "🔥", "count" => 1, "me" => true, "url" => nil}] =
             rendered["pleroma"]["emoji_reactions"]
  end

  test "renders mentions when the tag uses id instead of href" do
    {:ok, alice} = Users.create_local_user("alice")
    uuid = Ecto.UUID.generate()

    {:ok, note} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/with-mention-id/#{uuid}",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/with-mention-id/#{uuid}",
          "type" => "Note",
          "actor" => alice.ap_id,
          "content" => "hi",
          "tag" => [
            %{
              "type" => "Mention",
              "id" => "https://remote.example/users/bob",
              "name" => "@bob@remote.example"
            }
          ]
        }
      })

    rendered = StatusRenderer.render_status(note)

    assert [%{"username" => "bob", "acct" => "bob@remote.example", "url" => url}] =
             rendered["mentions"]

    assert url == Endpoint.url() <> "/@bob@remote.example"
  end

  test "filters mention tags that do not include href/id" do
    {:ok, alice} = Users.create_local_user("alice")
    uuid = Ecto.UUID.generate()

    {:ok, note} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/mention-without-href/#{uuid}",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/mention-without-href/#{uuid}",
          "type" => "Note",
          "actor" => alice.ap_id,
          "content" => "hi",
          "tag" => [
            %{
              "type" => "Mention",
              "name" => "@bob@remote.example"
            }
          ]
        }
      })

    rendered = StatusRenderer.render_status(note)

    assert rendered["mentions"] == []
  end

  test "renders mention acct based on href host even when name lacks a leading @" do
    {:ok, alice} = Users.create_local_user("alice")
    uuid = Ecto.UUID.generate()

    {:ok, note} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/mention-no-at/#{uuid}",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/mention-no-at/#{uuid}",
          "type" => "Note",
          "actor" => alice.ap_id,
          "content" => "hi",
          "tag" => [
            %{
              "type" => "Mention",
              "href" => "https://remote.example/users/mallory",
              "name" => "mallory"
            }
          ]
        }
      })

    rendered = StatusRenderer.render_status(note)

    assert [%{"username" => "mallory", "acct" => "mallory@remote.example"}] = rendered["mentions"]
  end

  test "falls back to a username-only acct when mention href has no host" do
    {:ok, alice} = Users.create_local_user("mention_acct_fallback_alice")
    uuid = Ecto.UUID.generate()

    {:ok, note} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/mention-no-host/#{uuid}",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/mention-no-host/#{uuid}",
          "type" => "Note",
          "actor" => alice.ap_id,
          "content" => "hi",
          "tag" => [
            %{
              "type" => "Mention",
              "href" => "acct:mallory@remote.example",
              "name" => "@mallory"
            }
          ]
        }
      })

    rendered = StatusRenderer.render_status(note)

    assert [%{"username" => "mallory", "acct" => "mallory"}] = rendered["mentions"]
  end

  test "falls back to href-derived username when mention name is missing" do
    {:ok, alice} = Users.create_local_user("alice")
    uuid = Ecto.UUID.generate()

    {:ok, note} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/mention-no-name/#{uuid}",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/mention-no-name/#{uuid}",
          "type" => "Note",
          "actor" => alice.ap_id,
          "content" => "hi",
          "tag" => [
            %{
              "type" => "Mention",
              "href" => "https://remote.example/users/stranger"
            }
          ]
        }
      })

    rendered = StatusRenderer.render_status(note)

    assert [%{"username" => "stranger", "acct" => "stranger@remote.example"}] =
             rendered["mentions"]
  end

  test "uses stored remote user records to build mention ids and acct values" do
    {:ok, alice} = Users.create_local_user("alice")
    uuid = Ecto.UUID.generate()

    {:ok, remote} =
      Users.create_user(%{
        nickname: "bob",
        domain: "remote.example",
        ap_id: "https://remote.example/users/bob",
        inbox: "https://remote.example/users/bob/inbox",
        outbox: "https://remote.example/users/bob/outbox",
        public_key: "remote-key",
        private_key: nil,
        local: false
      })

    {:ok, note} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/mention-known-user/#{uuid}",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/mention-known-user/#{uuid}",
          "type" => "Note",
          "actor" => alice.ap_id,
          "content" => "hi",
          "tag" => [
            %{
              "type" => "Mention",
              "href" => remote.ap_id,
              "name" => "@bob@remote.example"
            }
          ]
        }
      })

    rendered = StatusRenderer.render_status(note)

    assert [%{"id" => id, "acct" => "bob@remote.example", "username" => "bob"}] =
             rendered["mentions"]

    assert id == remote.id
  end

  test "renders custom emojis when icon urls are provided in lists" do
    {:ok, alice} = Users.create_local_user("alice")
    uuid = Ecto.UUID.generate()

    {:ok, note} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/emoji-icon-variants/#{uuid}",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/emoji-icon-variants/#{uuid}",
          "type" => "Note",
          "actor" => alice.ap_id,
          "content" => "hi",
          "tag" => [
            %{
              "type" => "Emoji",
              "name" => ":blob:",
              "icon" => %{"url" => [%{"href" => "https://cdn.example/blob.png"}]}
            },
            %{
              "type" => "Emoji",
              "name" => ":blob2:",
              "icon" => %{"url" => [%{"url" => "https://cdn.example/blob2.png"}]}
            },
            %{
              "type" => "Emoji",
              "name" => ":broken:",
              "icon" => %{}
            },
            %{
              "type" => "Emoji",
              "name" => 123,
              "icon" => %{"url" => "https://cdn.example/nope.png"}
            },
            %{
              "type" => "Hashtag"
            }
          ]
        }
      })

    rendered = StatusRenderer.render_status(note)

    assert [
             %{"shortcode" => "blob", "url" => "https://cdn.example/blob.png"},
             %{"shortcode" => "blob2", "url" => "https://cdn.example/blob2.png"}
           ] = rendered["emojis"]
  end

  test "renders custom emoji reactions with a url and host-qualified name" do
    {:ok, alice} = Users.create_local_user("alice")

    note_ap_id = "https://remote.example/objects/1"

    {:ok, note} =
      Objects.create_object(%{
        ap_id: note_ap_id,
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => note_ap_id,
          "type" => "Note",
          "actor" => alice.ap_id,
          "content" => "hello"
        }
      })

    activity = %{
      "id" => "https://remote.example/users/bob#reactions/1",
      "type" => "EmojiReact",
      "actor" => "https://remote.example/users/bob",
      "object" => note_ap_id,
      "content" => ":dinosaur:",
      "tag" => [
        %{
          "type" => "Emoji",
          "name" => "dinosaur",
          "icon" => %{"type" => "Image", "url" => "https://remote.example/emoji/dino.png"}
        }
      ]
    }

    assert {:ok, _react} = Pipeline.ingest(activity, local: false)

    rendered = StatusRenderer.render_status(note)

    assert [
             %{
               "name" => "dinosaur@remote.example",
               "count" => 1,
               "me" => false,
               "url" => "https://remote.example/emoji/dino.png"
             }
           ] = rendered["pleroma"]["emoji_reactions"]
  end

  test "renders mention acct based on href host when name omits a domain" do
    {:ok, alice} = Users.create_local_user("alice")

    {:ok, note} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/1",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/1",
          "type" => "Note",
          "actor" => alice.ap_id,
          "content" => "hi",
          "tag" => [
            %{
              "type" => "Mention",
              "href" => "https://remote.example/users/mallory",
              "name" => "@mallory"
            }
          ]
        }
      })

    rendered = StatusRenderer.render_status(note)

    assert [%{"acct" => "mallory@remote.example", "username" => "mallory"}] = rendered["mentions"]
  end

  test "renders hashtag urls when ActivityPub tag does not include href" do
    {:ok, alice} = Users.create_local_user("alice")

    {:ok, note} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/1",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/1",
          "type" => "Note",
          "actor" => alice.ap_id,
          "content" => "hi",
          "tag" => [
            %{
              "type" => "Hashtag",
              "name" => "#Elixir"
            }
          ]
        }
      })

    rendered = StatusRenderer.render_status(note)

    assert [%{"name" => "elixir", "url" => url}] = rendered["tags"]
    assert url == Endpoint.url() <> "/tags/elixir"
  end

  test "uses inserted_at when published is missing" do
    {:ok, alice} = Users.create_local_user("alice")

    {:ok, note} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/created-at",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/created-at",
          "type" => "Note",
          "actor" => alice.ap_id,
          "content" => "hello"
        }
      })

    rendered = StatusRenderer.render_status(note)

    assert rendered["created_at"] == DateTime.to_iso8601(note.inserted_at)
  end

  test "renders announces with missing objects as reblogs with nil status" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    {:ok, announce} =
      Objects.create_object(%{
        ap_id: "https://remote.example/activities/announce/1",
        type: "Announce",
        actor: bob.ap_id,
        object: "https://remote.example/objects/missing",
        local: false,
        data: %{
          "id" => "https://remote.example/activities/announce/1",
          "type" => "Announce",
          "actor" => bob.ap_id,
          "object" => "https://remote.example/objects/missing"
        }
      })

    rendered = StatusRenderer.render_status(announce, alice)

    assert rendered["reblog"] == nil
    assert rendered["visibility"] == "public"
  end

  test "falls back to an unknown account when announce actors are missing" do
    {:ok, alice} = Users.create_local_user("alice")

    {:ok, note} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/1",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/1",
          "type" => "Note",
          "actor" => alice.ap_id,
          "content" => "hello"
        }
      })

    {:ok, announce} =
      Objects.create_object(%{
        ap_id: "https://remote.example/activities/announce/with-missing-actor",
        type: "Announce",
        actor: nil,
        object: note.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/activities/announce/with-missing-actor",
          "type" => "Announce",
          "actor" => nil,
          "object" => note.ap_id
        }
      })

    rendered = StatusRenderer.render_status(announce, alice)

    assert rendered["account"]["id"] == "unknown"
    assert rendered["reblog"]["uri"] == note.ap_id
  end

  test "renders inReplyTo objects when they are provided as an id map" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    {:ok, parent} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/parent-map",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{"id" => "https://remote.example/objects/parent-map", "type" => "Note"}
      })

    {:ok, child} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/child-map",
        type: "Note",
        actor: bob.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/child-map",
          "type" => "Note",
          "actor" => bob.ap_id,
          "inReplyTo" => %{"id" => parent.ap_id}
        }
      })

    rendered = StatusRenderer.render_status(child)

    assert rendered["in_reply_to_id"] == parent.id
    assert rendered["in_reply_to_account_id"] == alice.id
  end

  test "renders nil in_reply_to fields when the parent cannot be found" do
    {:ok, alice} = Users.create_local_user("alice")

    {:ok, note} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/orphan",
        type: "Note",
        actor: alice.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/orphan",
          "type" => "Note",
          "actor" => alice.ap_id,
          "inReplyTo" => "https://remote.example/objects/missing"
        }
      })

    rendered = StatusRenderer.render_status(note)

    assert rendered["in_reply_to_id"] == nil
    assert rendered["in_reply_to_account_id"] == nil
  end

  test "includes Mastodon Status entity keys expected by clients" do
    {:ok, alice} = Users.create_local_user("alice")
    assert {:ok, create} = Publish.post_note(alice, "Hello")
    note = Objects.get_by_ap_id(create.object)

    rendered = StatusRenderer.render_status(note, alice)

    for key <- ~w(
      id
      created_at
      in_reply_to_id
      in_reply_to_account_id
      sensitive
      spoiler_text
      visibility
      language
      uri
      url
      replies_count
      reblogs_count
      favourites_count
      quotes_count
      edited_at
      content
      account
      media_attachments
      mentions
      tags
      emojis
      card
      poll
      quote
      quote_approval
      application
      filtered
    ) do
      assert Map.has_key?(rendered, key), "expected #{inspect(key)} to exist"
    end

    assert is_integer(rendered["replies_count"])
    assert is_integer(rendered["reblogs_count"])
    assert is_integer(rendered["favourites_count"])
    assert is_integer(rendered["quotes_count"])
    assert rendered["edited_at"] == nil
    assert rendered["application"] == nil
    assert rendered["filtered"] == []
  end

  test "computes replies_count from stored replies" do
    {:ok, alice} = Users.create_local_user("alice")
    assert {:ok, create} = Publish.post_note(alice, "Root")
    note = Objects.get_by_ap_id(create.object)

    assert {:ok, _reply} = Publish.post_note(alice, "Reply", in_reply_to: note.ap_id)

    rendered = StatusRenderer.render_status(note, alice)

    assert rendered["replies_count"] == 1
  end

  test "renders edited_at when a note has been edited" do
    {:ok, alice} = Users.create_local_user("alice")
    assert {:ok, create} = Publish.post_note(alice, "Hello")
    note = Objects.get_by_ap_id(create.object)

    assert {:ok, updated_note} =
             Objects.update_object(note, %{
               data: Map.put(note.data, "content", "Edited")
             })

    rendered = StatusRenderer.render_status(updated_note, alice)

    assert rendered["content"] =~ "Edited"
    assert rendered["edited_at"] == DateTime.to_iso8601(updated_note.updated_at)
  end

  test "reblog status bookmarked flag reflects the original status" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    {:ok, note} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/1",
        type: "Note",
        actor: bob.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/1",
          "type" => "Note",
          "actor" => bob.ap_id,
          "content" => "hello"
        }
      })

    {:ok, announce} =
      Objects.create_object(%{
        ap_id: "https://remote.example/activities/announce/1",
        type: "Announce",
        actor: bob.ap_id,
        object: note.ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/activities/announce/1",
          "type" => "Announce",
          "actor" => bob.ap_id,
          "object" => note.ap_id
        }
      })

    {:ok, _rel} =
      Relationships.upsert_relationship(%{
        type: "Bookmark",
        actor: alice.ap_id,
        object: note.ap_id,
        activity_ap_id: "https://egregoros.example/activities/bookmark/1"
      })

    rendered = StatusRenderer.render_status(announce, alice)

    assert rendered["reblog"]["uri"] == note.ap_id
    assert rendered["bookmarked"] == true
  end
end
