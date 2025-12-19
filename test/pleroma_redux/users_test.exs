defmodule PleromaRedux.UsersTest do
  use PleromaRedux.DataCase, async: true

  alias PleromaRedux.User
  alias PleromaRedux.Users

  test "create_user stores a user" do
    attrs = %{
      nickname: "alice",
      ap_id: "https://example.com/users/alice",
      inbox: "https://example.com/users/alice/inbox",
      outbox: "https://example.com/users/alice/outbox",
      public_key: "PUB",
      private_key: "PRIV",
      local: true
    }

    assert {:ok, %User{} = user} = Users.create_user(attrs)
    assert user.nickname == "alice"
    assert user.ap_id == attrs.ap_id
  end

  test "create_local_user generates keys and urls" do
    {:ok, user} = Users.create_local_user("bob")

    assert user.local == true
    assert user.nickname == "bob"
    assert user.ap_id == PleromaReduxWeb.Endpoint.url() <> "/users/bob"
    assert user.inbox == user.ap_id <> "/inbox"
    assert user.outbox == user.ap_id <> "/outbox"
    assert String.starts_with?(user.public_key, "-----BEGIN PUBLIC KEY-----")
    assert String.starts_with?(user.private_key, "-----BEGIN PRIVATE KEY-----")
  end

  test "ap_id is unique" do
    {:ok, _} = Users.create_user(%{
      nickname: "carol",
      ap_id: "https://example.com/users/carol",
      inbox: "https://example.com/users/carol/inbox",
      outbox: "https://example.com/users/carol/outbox",
      public_key: "PUB",
      private_key: "PRIV",
      local: true
    })

    assert {:error, changeset} =
             Users.create_user(%{
               nickname: "carol2",
               ap_id: "https://example.com/users/carol",
               inbox: "https://example.com/users/carol/inbox",
               outbox: "https://example.com/users/carol/outbox",
               public_key: "PUB",
               private_key: "PRIV",
               local: true
             })

    assert "has already been taken" in errors_on(changeset).ap_id
  end
end
