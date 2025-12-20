defmodule PleromaReduxWeb.ViewModels.StatusTest do
  use PleromaRedux.DataCase, async: true

  alias PleromaRedux.Activities.Note
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Users
  alias PleromaReduxWeb.ViewModels.Status

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
end
