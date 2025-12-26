defmodule PleromaRedux.PerformanceRegressionsTest do
  use PleromaRedux.DataCase, async: false

  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Users

  defp capture_repo_queries(fun) when is_function(fun, 0) do
    handler_id = {__MODULE__, System.unique_integer([:positive])}
    parent = self()

    :telemetry.attach(handler_id, [:pleroma_redux, :repo, :query], fn _event, _measurements, metadata, _config ->
      send(parent, {:repo_query, metadata})
    end, nil)

    try do
      result = fun.()
      {result, flush_repo_queries([])}
    after
      :telemetry.detach(handler_id)
    end
  end

  defp flush_repo_queries(acc) do
    receive do
      {:repo_query, metadata} -> flush_repo_queries([metadata | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "home timeline queries do not load follows into memory" do
    {:ok, alice} = Users.create_local_user("alice")

    bob_ap_id = "https://remote.example/users/bob"

    assert {:ok, _follow} =
             Pipeline.ingest(
               %{
                 "id" => "https://local.example/activities/follow/1",
                 "type" => "Follow",
                 "actor" => alice.ap_id,
                 "object" => bob_ap_id
               },
               local: true
             )

    assert {:ok, _note} =
             Objects.create_object(%{
               ap_id: "https://remote.example/objects/bob-1",
               type: "Note",
               actor: bob_ap_id,
               object: nil,
               data: %{
                 "id" => "https://remote.example/objects/bob-1",
                 "type" => "Note",
                 "actor" => bob_ap_id,
                 "to" => [bob_ap_id <> "/followers"],
                 "content" => "hello"
               },
               local: false
             })

    {_notes, notes_queries} =
      capture_repo_queries(fn -> Objects.list_home_notes(alice.ap_id, limit: 20) end)

    # Before optimization we ran a separate query to load all follow relationships, then another
    # query for the timeline. We want a single SQL query with a follow subquery instead.
    assert length(notes_queries) == 1

    {_statuses, statuses_queries} =
      capture_repo_queries(fn -> Objects.list_home_statuses(alice.ap_id, limit: 20) end)

    assert length(statuses_queries) == 1
  end
end

