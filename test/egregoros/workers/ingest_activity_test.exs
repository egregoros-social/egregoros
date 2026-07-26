defmodule Egregoros.Workers.IngestActivityTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.IngestError
  alias Egregoros.Workers.FetchActor
  alias Egregoros.Workers.IngestActivity

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

  # Permanent and transient failures must reach Oban differently, otherwise
  # max_attempts is decorative. A transient case is covered end to end in
  # test/egregoros/activities/undo_authorization_test.exs; here we pin that the
  # two classes do not collapse to the same outcome.
  test "permanent failures discard and transient failures retry" do
    assert IngestError.outcome(:permanent, :unknown_type) == {:discard, :unknown_type}
    assert IngestError.outcome(:transient, :target_unknown) == {:error, :target_unknown}

    job = %Oban.Job{
      args: %{
        "activity" => %{"id" => "https://remote.example/objects/1", "type" => "Unknown"}
      }
    }

    assert {:discard, :unknown_type} = IngestActivity.perform(job)
  end
end
