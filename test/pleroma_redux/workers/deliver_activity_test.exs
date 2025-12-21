defmodule PleromaRedux.Workers.DeliverActivityTest do
  use PleromaRedux.DataCase, async: true

  import Mox

  alias PleromaRedux.Users
  alias PleromaRedux.Workers.DeliverActivity

  setup :set_mox_from_context
  setup :verify_on_exit!

  test "performs delivery for a known user" do
    {:ok, user} = Users.create_local_user("alice")

    PleromaRedux.HTTP.Mock
    |> expect(:post, fn inbox_url, body, headers ->
      assert inbox_url == "https://remote.example/users/bob/inbox"
      assert is_binary(body)
      assert is_list(headers)

      assert {"content-type", "application/activity+json"} in headers
      assert {"accept", "application/activity+json"} in headers
      assert {"signature", _signature} = List.keyfind(headers, "signature", 0)

      {:ok, %{status: 202, body: "", headers: []}}
    end)

    job = %Oban.Job{
      args: %{
        "user_id" => user.id,
        "inbox_url" => "https://remote.example/users/bob/inbox",
        "activity" => %{"id" => "https://example.com/activities/1", "type" => "Follow"}
      }
    }

    assert :ok = DeliverActivity.perform(job)
  end

  test "discards jobs for unknown users" do
    job = %Oban.Job{
      args: %{
        "user_id" => 999_999,
        "inbox_url" => "https://remote.example/users/bob/inbox",
        "activity" => %{"id" => "https://example.com/activities/1", "type" => "Follow"}
      }
    }

    assert {:discard, :unknown_user} = DeliverActivity.perform(job)
  end

  test "returns an error when delivery fails" do
    {:ok, user} = Users.create_local_user("alice")

    PleromaRedux.HTTP.Mock
    |> expect(:post, fn _inbox_url, _body, _headers ->
      {:ok, %{status: 500, body: "", headers: []}}
    end)

    job = %Oban.Job{
      args: %{
        "user_id" => user.id,
        "inbox_url" => "https://remote.example/users/bob/inbox",
        "activity" => %{"id" => "https://example.com/activities/1", "type" => "Follow"}
      }
    }

    assert {:error, {:http_error, 500, _response}} = DeliverActivity.perform(job)
  end

  test "discards jobs with invalid arguments" do
    assert {:discard, :invalid_args} = DeliverActivity.perform(%Oban.Job{args: %{}})
  end
end

