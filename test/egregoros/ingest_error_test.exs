defmodule Egregoros.IngestErrorTest do
  use ExUnit.Case, async: true

  alias Egregoros.IngestError

  describe "classify/1" do
    test "targeting and validation rejections are permanent" do
      for reason <- [
            :not_targeted,
            :invalid,
            :unknown_type,
            :local_id,
            :voter_not_permitted,
            :too_long
          ] do
        assert IngestError.classify(reason) == :permanent,
               "expected #{inspect(reason)} to be permanent"
      end
    end

    test "ordering races are transient, so the job is retried" do
      for reason <- [:target_unknown, :question_not_found] do
        assert IngestError.classify(reason) == :transient,
               "expected #{inspect(reason)} to be transient"
      end
    end

    # A changeset reaching the worker is a failed write from Objects.upsert_object,
    # not a failed validation — cast/validate failures became :invalid upstream.
    test "a failed write is transient" do
      changeset = Ecto.Changeset.change({%{}, %{}})

      assert IngestError.classify(changeset) == :transient
    end

    test "an unrecognized reason defaults to permanent" do
      assert IngestError.classify(:something_nobody_classified) == :permanent
      assert IngestError.classify("a string") == :permanent
      assert IngestError.classify({:nested, :tuple}) == :permanent
    end
  end

  describe "outcome/2" do
    test "permanent discards, so the job is not retried" do
      assert IngestError.outcome(:permanent, :not_targeted) == {:discard, :not_targeted}
    end

    test "transient returns an error, so Oban retries within max_attempts" do
      assert IngestError.outcome(:transient, :some_reason) == {:error, :some_reason}
    end

    test "duplicate succeeds, because the work is already done" do
      assert IngestError.outcome(:duplicate, :already_processed) == :ok
    end
  end

  describe "oban_outcome/1" do
    test "maps a reason straight through to its class's outcome" do
      assert IngestError.oban_outcome(:not_targeted) == {:discard, :not_targeted}
      assert IngestError.oban_outcome(:unclassified) == {:discard, :unclassified}
    end
  end

  # Guards the acceptance criterion "no pipeline error path reaches the worker
  # without a defined outcome". Compares the error atoms actually returned on the
  # ingest path against the classified set, in BOTH directions: an unclassified
  # new error fails, and so does a classified atom that no longer exists.
  describe "coverage of the ingest path" do
    @ingest_path [
      "lib/egregoros/pipeline.ex",
      "lib/egregoros/inbox_targeting.ex",
      "lib/egregoros/activity_registry.ex",
      "lib/egregoros/activity_pub/type_normalizer.ex"
    ]

    # Returned by modules off the scanned path, or not as a bare atom literal.
    # Listed explicitly so the set comparison below stays honest.
    @known_offpath [:invalid, :question_not_found, :target_unknown]

    # Produced on the path but consumed before it can reach the worker. A purely
    # syntactic scan cannot see this, so the reachability call is recorded here.
    # :invalid_type is caught in TypeNormalizer.normalize_incoming/1 and rewritten
    # to :invalid (type_normalizer.ex:42).
    @never_escapes [:invalid_type]

    test "the classified set matches the errors the ingest path can return" do
      files = @ingest_path ++ Path.wildcard("lib/egregoros/activities/*.ex")

      # Every file must exist — a rename should fail here, not silently shrink
      # the scan.
      for file <- @ingest_path, do: assert(File.exists?(file), "missing #{file}")

      found =
        files
        |> Enum.flat_map(fn file ->
          ~r/\{:error,\s*:([a-z_0-9]+)\}/
          |> Regex.scan(File.read!(file))
          |> Enum.map(fn [_, atom] -> String.to_atom(atom) end)
        end)
        |> MapSet.new()
        |> MapSet.union(MapSet.new(@known_offpath))
        |> MapSet.difference(MapSet.new(@never_escapes))

      classified = MapSet.new(IngestError.known_reasons())

      unclassified = MapSet.difference(found, classified) |> Enum.sort()
      stale = MapSet.difference(classified, found) |> Enum.sort()

      assert unclassified == [],
             """
             Unclassified ingest errors: #{inspect(unclassified)}

             They fall through to the permanent default, so they are discarded \
             without retry. Add each to @permanent, @transient, or @duplicate in \
             Egregoros.IngestError — or to @never_escapes here if it is consumed \
             before reaching the worker.
             """

      assert stale == [],
             """
             Classified but never returned: #{inspect(stale)}

             Remove them from Egregoros.IngestError, or extend @ingest_path / \
             @known_offpath here if they moved.
             """
    end
  end
end
