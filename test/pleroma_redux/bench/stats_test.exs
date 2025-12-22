defmodule PleromaRedux.Bench.StatsTest do
  use ExUnit.Case, async: true

  alias PleromaRedux.Bench.Stats

  test "summary/1 computes common percentiles" do
    assert %{
             samples: 5,
             min: 10,
             p50: 30,
             p95: 50,
             max: 50,
             avg: 30.0
           } = Stats.summary([10, 20, 30, 40, 50])
  end

  test "summary/1 handles a single sample" do
    assert %{
             samples: 1,
             min: 123,
             p50: 123,
             p95: 123,
             max: 123,
             avg: 123.0
           } = Stats.summary([123])
  end
end
