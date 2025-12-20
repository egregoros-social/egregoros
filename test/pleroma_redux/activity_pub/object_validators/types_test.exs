defmodule PleromaRedux.ActivityPub.ObjectValidators.TypesTest do
  use ExUnit.Case, async: true

  alias PleromaRedux.ActivityPub.ObjectValidators.Types.ObjectID
  alias PleromaRedux.ActivityPub.ObjectValidators.Types.Recipients
  alias PleromaRedux.ActivityPub.ObjectValidators.Types.DateTime, as: APDateTime

  describe "ObjectID" do
    test "casts a non-empty string" do
      assert {:ok, "https://example.com/objects/1"} =
               Ecto.Type.cast(ObjectID, "https://example.com/objects/1")
    end

    test "trims whitespace" do
      assert {:ok, "https://example.com/objects/1"} =
               Ecto.Type.cast(ObjectID, "  https://example.com/objects/1  ")
    end

    test "casts a map with an id" do
      assert {:ok, "https://example.com/objects/1"} =
               Ecto.Type.cast(ObjectID, %{"id" => "https://example.com/objects/1"})
    end

    test "casts a nested id map" do
      assert {:ok, "https://example.com/objects/1"} =
               Ecto.Type.cast(ObjectID, %{"id" => %{"id" => "https://example.com/objects/1"}})
    end

    test "rejects empty strings" do
      assert :error = Ecto.Type.cast(ObjectID, "   ")
    end
  end

  describe "Recipients" do
    test "casts a string into a singleton list" do
      assert {:ok, ["https://example.com/users/alice"]} =
               Ecto.Type.cast(Recipients, "https://example.com/users/alice")
    end

    test "casts a map into a singleton list" do
      assert {:ok, ["https://example.com/users/alice"]} =
               Ecto.Type.cast(Recipients, %{"id" => "https://example.com/users/alice"})
    end

    test "casts a list and drops invalid entries" do
      assert {:ok, ["https://example.com/users/alice", "https://example.com/users/bob"]} =
               Ecto.Type.cast(Recipients, [
                 "https://example.com/users/bob",
                 "   ",
                 %{},
                 %{"id" => "https://example.com/users/alice"}
               ])
    end

    test "returns nil for nil" do
      assert {:ok, nil} = Ecto.Type.cast(Recipients, nil)
    end
  end

  describe "DateTime" do
    test "casts iso8601 values" do
      assert {:ok, "2020-01-01T00:00:00Z"} = Ecto.Type.cast(APDateTime, "2020-01-01T00:00:00Z")
    end

    test "treats missing offsets as UTC" do
      assert {:ok, "2020-01-01T00:00:00Z"} = Ecto.Type.cast(APDateTime, "2020-01-01T00:00:00")
    end

    test "rejects invalid values" do
      assert :error = Ecto.Type.cast(APDateTime, "nope")
    end
  end
end

