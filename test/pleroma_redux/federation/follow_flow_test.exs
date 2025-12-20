defmodule PleromaRedux.Federation.FollowFlowTest do
  use PleromaRedux.DataCase, async: true

  import Mox

  alias PleromaRedux.Objects
  alias PleromaRedux.Users
  alias PleromaRedux.Workers.DeliverActivity

  test "follow_remote/2 discovers actor via WebFinger, stores user, and delivers Follow" do
    {:ok, local} = Users.create_local_user("alice")

    actor_url = "https://remote.example/users/bob"

    PleromaRedux.HTTP.Mock
    |> expect(:get, fn url, _headers ->
      assert url ==
               "https://remote.example/.well-known/webfinger?resource=acct:bob@remote.example"

      {:ok,
       %{
         status: 200,
         body: %{
           "links" => [
             %{
               "rel" => "self",
               "type" => "application/activity+json",
               "href" => actor_url
             }
           ]
         },
         headers: []
       }}
    end)
    |> expect(:get, fn url, _headers ->
      assert url == actor_url

      {:ok,
       %{
         status: 200,
         body: %{
           "id" => actor_url,
           "type" => "Person",
           "preferredUsername" => "bob",
           "inbox" => "https://remote.example/users/bob/inbox",
           "outbox" => "https://remote.example/users/bob/outbox",
           "publicKey" => %{
             "id" => actor_url <> "#main-key",
             "owner" => actor_url,
             "publicKeyPem" => "-----BEGIN PUBLIC KEY-----\nMIIB...\n-----END PUBLIC KEY-----\n"
           }
         },
         headers: []
       }}
    end)
    |> expect(:post, fn url, body, _headers ->
      assert url == "https://remote.example/users/bob/inbox"

      decoded = Jason.decode!(body)
      assert decoded["type"] == "Follow"
      assert decoded["actor"] == local.ap_id
      assert decoded["object"] == actor_url

      {:ok, %{status: 202, body: "", headers: []}}
    end)

    assert {:ok, remote} = PleromaRedux.Federation.follow_remote(local, "bob@remote.example")

    args =
      all_enqueued(worker: DeliverActivity)
      |> Enum.map(& &1.args)
      |> Enum.find(fn
        %{"activity" => %{"type" => "Follow"}} -> true
        _ -> false
      end)

    assert is_map(args)
    assert :ok = perform_job(DeliverActivity, args)

    assert remote.local == false
    assert remote.ap_id == actor_url
    assert remote.inbox == "https://remote.example/users/bob/inbox"

    assert Objects.get_by_type_actor_object("Follow", local.ap_id, actor_url)
  end
end
