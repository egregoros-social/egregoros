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

    assert rendered["in_reply_to_id"] == Integer.to_string(parent.id)
    assert rendered["in_reply_to_account_id"] == Integer.to_string(alice.id)
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
        data: %{"id" => "https://remote.example/objects/media/1", "type" => "Document"}
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
               "description" => "clip",
               "blurhash" => "abc"
             }
           ] = rendered["media_attachments"]

    assert media_id == Integer.to_string(media_object.id)
    assert url == Endpoint.url() <> "/media/clip.mp4"
    assert preview == url
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

    assert rendered["in_reply_to_id"] == Integer.to_string(parent.id)
    assert rendered["in_reply_to_account_id"] == Integer.to_string(alice.id)
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
end
