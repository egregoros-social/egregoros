defmodule Egregoros.Workers.RefreshPollTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Repo
  alias Egregoros.Users
  alias Egregoros.Workers.RefreshPoll
  alias EgregorosWeb.Endpoint

  @as_public "https://www.w3.org/ns/activitystreams#Public"

  describe "maybe_enqueue/1" do
    test "enqueues refresh for open remote poll" do
      ap_id = "https://remote.example/objects/" <> Ecto.UUID.generate()

      poll = %Egregoros.Object{
        type: "Question",
        local: false,
        ap_id: ap_id,
        data: %{"closed" => nil}
      }

      assert :ok = RefreshPoll.maybe_enqueue(poll)

      assert_enqueued(
        worker: RefreshPoll,
        queue: "federation_incoming",
        args: %{"ap_id" => ap_id}
      )
    end

    test "skips enqueue for closed polls" do
      ap_id = "https://remote.example/objects/" <> Ecto.UUID.generate()

      poll = %Egregoros.Object{
        type: "Question",
        local: false,
        ap_id: ap_id,
        data: %{"closed" => "2020-01-01T00:00:00Z"}
      }

      assert :ok = RefreshPoll.maybe_enqueue(poll)
      refute_enqueued(worker: RefreshPoll)
    end

    test "assumes open when closed is unparseable" do
      ap_id = "https://remote.example/objects/" <> Ecto.UUID.generate()

      poll = %Egregoros.Object{
        type: "Question",
        local: false,
        ap_id: ap_id,
        data: %{"closed" => "not-a-datetime"}
      }

      assert :ok = RefreshPoll.maybe_enqueue(poll)
      assert_enqueued(worker: RefreshPoll, args: %{"ap_id" => ap_id})
    end

    test "does not enqueue for local polls" do
      ap_id = Endpoint.url() <> "/objects/" <> Ecto.UUID.generate()

      poll = %Egregoros.Object{
        type: "Question",
        local: true,
        ap_id: ap_id,
        data: %{"closed" => nil}
      }

      assert :ok = RefreshPoll.maybe_enqueue(poll)
      refute_enqueued(worker: RefreshPoll)
    end
  end

  describe "perform/1" do
    test "returns :ok when the poll isn't present locally" do
      ap_id = "https://remote.example/objects/" <> Ecto.UUID.generate()
      assert :ok = RefreshPoll.perform(%Oban.Job{args: %{"ap_id" => ap_id}})
    end

    test "returns :ok for local polls" do
      ap_id = Endpoint.url() <> "/objects/" <> Ecto.UUID.generate()

      {:ok, alice} = Users.create_local_user("refresh_poll_alice")

      question = %{
        "id" => ap_id,
        "type" => "Question",
        "attributedTo" => alice.ap_id,
        "context" => Endpoint.url() <> "/contexts/" <> Ecto.UUID.generate(),
        "to" => [@as_public],
        "oneOf" => [%{"name" => "A", "replies" => %{"totalItems" => 0}}]
      }

      assert {:ok, _poll} = Pipeline.ingest(question, local: true)

      assert :ok = RefreshPoll.perform(%Oban.Job{args: %{"ap_id" => ap_id}})
    end

    test "refreshes remote polls and ingests the updated Question" do
      ap_id = "https://remote.example/objects/" <> Ecto.UUID.generate()

      {:ok, remote_actor} =
        Users.create_user(%{
          nickname: "refresh_poll_remote",
          ap_id: "https://remote.example/users/pollcreator",
          inbox: "https://remote.example/users/pollcreator/inbox",
          outbox: "https://remote.example/users/pollcreator/outbox",
          public_key: "pubkey",
          local: false
        })

      initial_question = %{
        "id" => ap_id,
        "type" => "Question",
        "attributedTo" => remote_actor.ap_id,
        "context" => "https://remote.example/contexts/" <> Ecto.UUID.generate(),
        "to" => [@as_public],
        "oneOf" => [
          %{"name" => "A", "replies" => %{"totalItems" => 0}},
          %{"name" => "B", "replies" => %{"totalItems" => 0}}
        ],
        "closed" => DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.to_iso8601()
      }

      assert {:ok, _poll} = Pipeline.ingest(initial_question, local: false)

      updated_question =
        initial_question
        |> put_in(["oneOf", Access.at(0), "replies", "totalItems"], 5)
        |> put_in(["oneOf", Access.at(1), "replies", "totalItems"], 2)

      stub(Egregoros.HTTP.Mock, :get, fn url, headers ->
        if url == ap_id do
          {:ok, %{status: 200, body: updated_question, headers: []}}
        else
          Egregoros.HTTP.Stub.get(url, headers)
        end
      end)

      assert :ok = RefreshPoll.perform(%Oban.Job{args: %{"ap_id" => ap_id}})

      poll = Objects.get_by_ap_id(ap_id)
      assert poll

      [a, b] = poll.data["oneOf"]
      assert a["replies"]["totalItems"] == 5
      assert b["replies"]["totalItems"] == 2
    end

    test "ignores updates that don't match the poll id" do
      ap_id = "https://remote.example/objects/" <> Ecto.UUID.generate()

      question = %{
        "id" => ap_id,
        "type" => "Question",
        "attributedTo" => "https://remote.example/users/pollcreator",
        "context" => "https://remote.example/contexts/" <> Ecto.UUID.generate(),
        "to" => [@as_public],
        "oneOf" => [%{"name" => "A", "replies" => %{"totalItems" => 0}}]
      }

      assert {:ok, _poll} = Pipeline.ingest(question, local: false)

      stub(Egregoros.HTTP.Mock, :get, fn url, headers ->
        if url == ap_id do
          {:ok,
           %{
             status: 200,
             body: %{"id" => "https://other.example/objects/1", "type" => "Question"},
             headers: []
           }}
        else
          Egregoros.HTTP.Stub.get(url, headers)
        end
      end)

      assert :ok = RefreshPoll.perform(%Oban.Job{args: %{"ap_id" => ap_id}})
    end

    test "ignores invalid json bodies" do
      ap_id = "https://remote.example/objects/" <> Ecto.UUID.generate()

      question = %{
        "id" => ap_id,
        "type" => "Question",
        "attributedTo" => "https://remote.example/users/pollcreator",
        "context" => "https://remote.example/contexts/" <> Ecto.UUID.generate(),
        "to" => [@as_public],
        "oneOf" => [%{"name" => "A", "replies" => %{"totalItems" => 0}}]
      }

      assert {:ok, _poll} = Pipeline.ingest(question, local: false)

      stub(Egregoros.HTTP.Mock, :get, fn url, headers ->
        if url == ap_id do
          {:ok, %{status: 200, body: "not-json", headers: []}}
        else
          Egregoros.HTTP.Stub.get(url, headers)
        end
      end)

      assert :ok = RefreshPoll.perform(%Oban.Job{args: %{"ap_id" => ap_id}})
    end

    test "does not retry for 404 responses" do
      ap_id = "https://remote.example/objects/" <> Ecto.UUID.generate()

      question = %{
        "id" => ap_id,
        "type" => "Question",
        "attributedTo" => "https://remote.example/users/pollcreator",
        "context" => "https://remote.example/contexts/" <> Ecto.UUID.generate(),
        "to" => [@as_public],
        "oneOf" => [%{"name" => "A", "replies" => %{"totalItems" => 0}}]
      }

      assert {:ok, _poll} = Pipeline.ingest(question, local: false)

      stub(Egregoros.HTTP.Mock, :get, fn url, headers ->
        if url == ap_id do
          {:ok, %{status: 404, body: %{}, headers: []}}
        else
          Egregoros.HTTP.Stub.get(url, headers)
        end
      end)

      assert :ok = RefreshPoll.perform(%Oban.Job{args: %{"ap_id" => ap_id}})
    end

    test "returns :ok for unsafe poll urls" do
      ap_id = "http://127.0.0.1/objects/" <> Ecto.UUID.generate()

      _ =
        %Object{}
        |> Object.changeset(%{
          ap_id: ap_id,
          type: "Question",
          local: false,
          data: %{
            "id" => ap_id,
            "type" => "Question",
            "oneOf" => [%{"name" => "A", "replies" => %{"totalItems" => 0}}]
          }
        })
        |> Repo.insert!()

      assert :ok = RefreshPoll.perform(%Oban.Job{args: %{"ap_id" => ap_id}})
    end

    test "returns an error for server errors" do
      ap_id = "https://remote.example/objects/" <> Ecto.UUID.generate()

      question = %{
        "id" => ap_id,
        "type" => "Question",
        "attributedTo" => "https://remote.example/users/pollcreator",
        "context" => "https://remote.example/contexts/" <> Ecto.UUID.generate(),
        "to" => [@as_public],
        "oneOf" => [%{"name" => "A", "replies" => %{"totalItems" => 0}}]
      }

      assert {:ok, _poll} = Pipeline.ingest(question, local: false)

      stub(Egregoros.HTTP.Mock, :get, fn url, headers ->
        if url == ap_id do
          {:ok, %{status: 500, body: %{}, headers: []}}
        else
          Egregoros.HTTP.Stub.get(url, headers)
        end
      end)

      assert {:error, {:http_status, 500}} =
               RefreshPoll.perform(%Oban.Job{args: %{"ap_id" => ap_id}})
    end

    test "does not retry when SignedFetch returns a 404 without a body" do
      ap_id = "https://remote.example/objects/" <> Ecto.UUID.generate()

      question = %{
        "id" => ap_id,
        "type" => "Question",
        "attributedTo" => "https://remote.example/users/pollcreator",
        "context" => "https://remote.example/contexts/" <> Ecto.UUID.generate(),
        "to" => [@as_public],
        "oneOf" => [%{"name" => "A", "replies" => %{"totalItems" => 0}}]
      }

      assert {:ok, _poll} = Pipeline.ingest(question, local: false)

      stub(Egregoros.HTTP.Mock, :get, fn url, headers ->
        if url == ap_id do
          {:ok, %{status: 404}}
        else
          Egregoros.HTTP.Stub.get(url, headers)
        end
      end)

      assert :ok = RefreshPoll.perform(%Oban.Job{args: %{"ap_id" => ap_id}})
    end

    test "propagates SignedFetch errors" do
      ap_id = "https://remote.example/objects/" <> Ecto.UUID.generate()

      question = %{
        "id" => ap_id,
        "type" => "Question",
        "attributedTo" => "https://remote.example/users/pollcreator",
        "context" => "https://remote.example/contexts/" <> Ecto.UUID.generate(),
        "to" => [@as_public],
        "oneOf" => [%{"name" => "A", "replies" => %{"totalItems" => 0}}]
      }

      assert {:ok, _poll} = Pipeline.ingest(question, local: false)

      stub(Egregoros.HTTP.Mock, :get, fn url, headers ->
        if url == ap_id do
          {:error, :timeout}
        else
          Egregoros.HTTP.Stub.get(url, headers)
        end
      end)

      assert {:error, :timeout} = RefreshPoll.perform(%Oban.Job{args: %{"ap_id" => ap_id}})
    end

    test "discards invalid args" do
      assert {:discard, :invalid_args} = RefreshPoll.perform(%Oban.Job{args: %{}})
    end
  end
end
