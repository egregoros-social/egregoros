defmodule Egregoros.Workers.IngestActivityTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.Workers.IngestActivity
  alias Egregoros.Workers.FetchActor

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

  test "enqueues actor fetches for mentions inside ingested activities" do
    job = %Oban.Job{
      args: %{
        "activity" => %{
          "id" => "https://remote.example/activities/create/1",
          "type" => "Create",
          "actor" => "https://remote.example/users/alice",
          "object" => %{
            "id" => "https://remote.example/objects/1",
            "type" => "Note",
            "attributedTo" => "https://remote.example/users/alice",
            "content" => "Hello @bob@remote2.example",
            "tag" => [
              %{
                "type" => "Mention",
                "href" => "https://remote2.example/users/bob",
                "name" => "@bob@remote2.example"
              }
            ]
          }
        }
      }
    }

    assert :ok = IngestActivity.perform(job)

    assert_enqueued(
      worker: FetchActor,
      args: %{"ap_id" => "https://remote2.example/users/bob"}
    )
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
