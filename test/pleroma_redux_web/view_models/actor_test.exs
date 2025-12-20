defmodule PleromaReduxWeb.ViewModels.ActorTest do
  use PleromaRedux.DataCase, async: true

  alias PleromaRedux.Users
  alias PleromaReduxWeb.ViewModels.Actor

  test "local actors use a short handle" do
    {:ok, user} = Users.create_local_user("alice")

    assert %{handle: "@alice"} = Actor.card(user.ap_id)
  end

  test "remote actors include the host in the handle" do
    {:ok, remote} =
      Users.create_user(%{
        nickname: "bob",
        ap_id: "https://remote.example/users/bob",
        inbox: "https://remote.example/users/bob/inbox",
        outbox: "https://remote.example/users/bob/outbox",
        public_key: "PUB",
        private_key: nil,
        local: false
      })

    assert %{handle: "@bob@remote.example"} = Actor.card(remote.ap_id)
  end
end
