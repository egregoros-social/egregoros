defmodule Egregoros.Types.JsonValueTest do
  use ExUnit.Case, async: true

  alias Egregoros.Types.JsonValue

  test "cast/1 accepts maps, lists, binaries, and nil" do
    assert {:ok, %{"a" => 1}} = JsonValue.cast(%{"a" => 1})
    assert {:ok, [1, 2, 3]} = JsonValue.cast([1, 2, 3])
    assert {:ok, "ok"} = JsonValue.cast("ok")
    assert {:ok, nil} = JsonValue.cast(nil)
  end

  test "cast/1 rejects other terms" do
    assert :error = JsonValue.cast(123)
    assert :error = JsonValue.cast(:atom)
  end

  test "dump/1 and load/1 roundtrip allowed values" do
    value = %{"a" => [1, 2, 3]}
    assert {:ok, ^value} = JsonValue.dump(value)
    assert {:ok, ^value} = JsonValue.load(value)

    assert {:ok, nil} = JsonValue.dump(nil)
    assert {:ok, nil} = JsonValue.load(nil)
  end
end
