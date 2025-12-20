defmodule PleromaRedux.Federation.DeliveryTest do
  use PleromaRedux.DataCase, async: true

  import Mox

  alias PleromaRedux.Federation.Delivery
  alias PleromaRedux.Users
  alias PleromaRedux.Workers.DeliverActivity

  test "deliver posts a signed activity to the inbox" do
    {:ok, user} = Users.create_local_user("alice")

    inbox = "https://remote.example/users/bob/inbox"

    activity = %{
      "id" => "https://local.example/activities/follow/1",
      "type" => "Follow",
      "actor" => user.ap_id,
      "object" => "https://remote.example/users/bob"
    }

    body = Jason.encode!(activity)

    expected_digest = "SHA-256=" <> (:crypto.hash(:sha256, body) |> Base.encode64())

    PleromaRedux.HTTP.Mock
    |> expect(:post, fn ^inbox, ^body, headers ->
      assert {"content-type", "application/activity+json"} in headers
      assert {"accept", "application/activity+json"} in headers
      assert {"digest", expected_digest} in headers

      assert {"content-length", Integer.to_string(byte_size(body))} in headers

      assert Enum.any?(headers, fn
               {"signature", value} ->
                 is_binary(value) and String.contains?(value, "keyId=\"#{user.ap_id}#main-key\"")

               _ ->
                 false
             end)

      {:ok, %{status: 202, body: "", headers: []}}
    end)

    assert {:ok, _job} = Delivery.deliver(user, inbox, activity)

    assert_enqueued(
      worker: DeliverActivity,
      queue: "federation_outgoing",
      args: %{"user_id" => user.id, "inbox_url" => inbox, "activity" => activity}
    )

    assert :ok =
             perform_job(DeliverActivity, %{
               "user_id" => user.id,
               "inbox_url" => inbox,
               "activity" => activity
             })
  end
end
