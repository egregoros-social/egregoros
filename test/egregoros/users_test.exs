defmodule Egregoros.UsersTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.User
  alias Egregoros.Users

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

  test "create_user allows remote user without private key" do
    attrs = %{
      nickname: "remote",
      ap_id: "https://remote.example/users/remote",
      inbox: "https://remote.example/users/remote/inbox",
      outbox: "https://remote.example/users/remote/outbox",
      public_key: "PUB",
      private_key: nil,
      local: false
    }

    assert {:ok, %User{} = user} = Users.create_user(attrs)
    assert user.local == false
    assert is_nil(user.private_key)
  end

  test "create_local_user generates keys and urls" do
    {:ok, user} = Users.create_local_user("bob")

    assert user.local == true
    assert user.nickname == "bob"
    assert user.ap_id == EgregorosWeb.Endpoint.url() <> "/users/bob"
    assert user.inbox == user.ap_id <> "/inbox"
    assert user.outbox == user.ap_id <> "/outbox"
    assert String.starts_with?(user.public_key, "-----BEGIN PUBLIC KEY-----")
    assert String.starts_with?(user.private_key, "-----BEGIN PRIVATE KEY-----")
  end

  test "get_or_create_local_user returns existing" do
    {:ok, user} = Users.create_local_user("dora")
    {:ok, fetched} = Users.get_or_create_local_user("dora")
    assert fetched.id == user.id
  end

  test "ap_id is unique" do
    {:ok, _} =
      Users.create_user(%{
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

  test "search_mentions/2 finds local users by nickname" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, alicia} = Users.create_local_user("alicia")

    results = Users.search_mentions("ali", limit: 10)

    assert Enum.any?(results, &(&1.id == alice.id))
    assert Enum.any?(results, &(&1.id == alicia.id))
  end

  test "search_mentions/2 finds remote users when query includes a domain" do
    {:ok, remote} =
      Users.create_user(%{
        nickname: "toast",
        domain: "donotsta.re",
        ap_id: "https://donotsta.re/users/toast",
        inbox: "https://donotsta.re/users/toast/inbox",
        outbox: "https://donotsta.re/users/toast/outbox",
        public_key: "PUB",
        private_key: nil,
        local: false
      })

    results = Users.search_mentions("toast@dono", limit: 10)

    assert Enum.any?(results, &(&1.id == remote.id))
  end
end
