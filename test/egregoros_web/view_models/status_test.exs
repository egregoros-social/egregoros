defmodule EgregorosWeb.ViewModels.StatusTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.Activities.Note
  alias Egregoros.Interactions
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Users
  alias EgregorosWeb.ViewModels.Status

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
end
