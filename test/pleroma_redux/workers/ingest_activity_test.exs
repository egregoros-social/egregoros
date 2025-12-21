defmodule PleromaRedux.Workers.IngestActivityTest do
  use PleromaRedux.DataCase, async: true

  alias PleromaRedux.Workers.IngestActivity

  test "ingests activities as remote objects" do
    job = %Oban.Job{
      args: %{
        "activity" => %{
          "id" => "https://remote.example/objects/1",
          "type" => "Note",
          "attributedTo" => "https://remote.example/users/alice",
          "content" => "Hello"
        }
      }
    }

    assert :ok = IngestActivity.perform(job)
  end

  test "discards invalid activities" do
    job = %Oban.Job{
      args: %{
        "activity" => %{"id" => "https://remote.example/objects/1", "type" => "Unknown"}
      }
    }

    assert {:discard, :unknown_type} = IngestActivity.perform(job)
  end

  test "discards jobs with invalid arguments" do
    assert {:discard, :invalid_args} = IngestActivity.perform(%Oban.Job{args: %{}})
    assert {:discard, :invalid_args} = IngestActivity.perform(%Oban.Job{args: %{"activity" => 1}})
  end
end

