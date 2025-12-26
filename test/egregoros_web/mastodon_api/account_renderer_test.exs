defmodule EgregorosWeb.MastodonAPI.AccountRendererTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.Users
  alias EgregorosWeb.MastodonAPI.AccountRenderer

  test "escapes local bios as text" do
    {:ok, user} = Users.create_local_user("alice")
    {:ok, user} = Users.update_profile(user, %{bio: "<script>alert(1)</script>"})

    rendered = AccountRenderer.render_account(user)

    assert rendered["note"] =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
    refute rendered["note"] =~ "<script"
  end

  test "sanitizes remote bios as html" do
    {:ok, user} =
      Users.create_user(%{
        nickname: "bob",
        ap_id: "https://remote.example/users/bob",
        inbox: "https://remote.example/users/bob/inbox",
        outbox: "https://remote.example/users/bob/outbox",
        public_key: "PUB",
        private_key: nil,
        local: false,
        bio: "<p>ok</p><script>alert(1)</script>"
      })

    rendered = AccountRenderer.render_account(user)

    assert rendered["note"] =~ "<p>ok</p>"
    refute rendered["note"] =~ "<script"
  end

  test "renders remote avatar urls relative to their ap id host" do
    {:ok, user} =
      Users.create_user(%{
        nickname: "bob",
        ap_id: "https://remote.example/users/bob",
        inbox: "https://remote.example/users/bob/inbox",
        outbox: "https://remote.example/users/bob/outbox",
        public_key: "PUB",
        private_key: nil,
        local: false,
        avatar_url: "/media/avatar.png"
      })

    rendered = AccountRenderer.render_account(user)
    assert rendered["avatar"] == "https://remote.example/media/avatar.png"
    assert rendered["avatar_static"] == "https://remote.example/media/avatar.png"
  end

  test "renders account url as a local profile url" do
    {:ok, user} = Users.create_local_user("alice")

    rendered = AccountRenderer.render_account(user)

    assert rendered["url"] == EgregorosWeb.Endpoint.url() <> "/@alice"
  end

  test "renders remote account url as a local profile url" do
    {:ok, user} =
      Users.create_user(%{
        nickname: "bob",
        ap_id: "https://remote.example/users/bob",
        inbox: "https://remote.example/users/bob/inbox",
        outbox: "https://remote.example/users/bob/outbox",
        public_key: "PUB",
        private_key: nil,
        local: false
      })

    rendered = AccountRenderer.render_account(user)

    assert rendered["url"] == EgregorosWeb.Endpoint.url() <> "/@bob@remote.example"
  end

  test "renders remote account acct with non-default ports" do
    {:ok, user} =
      Users.create_user(%{
        nickname: "bob",
        ap_id: "https://remote.example:8443/users/bob",
        inbox: "https://remote.example:8443/users/bob/inbox",
        outbox: "https://remote.example:8443/users/bob/outbox",
        public_key: "PUB",
        private_key: nil,
        local: false
      })

    rendered = AccountRenderer.render_account(user)

    assert rendered["acct"] == "bob@remote.example:8443"
  end
end
