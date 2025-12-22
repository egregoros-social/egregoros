defmodule PleromaRedux.Bench.RunnerTest do
  use ExUnit.Case, async: true

  alias PleromaRedux.Bench.Runner

  test "measure/2 collects N samples with warmup" do
    Process.put(:bench_times, [0, 5, 5, 20, 20, 50, 50, 90])

    now_fun = fn ->
      [t | rest] = Process.get(:bench_times)
      Process.put(:bench_times, rest)
      t
    end

    result =
      Runner.measure(fn -> :ok end,
        warmup: 1,
        iterations: 3,
        now_us: now_fun,
        track_queries?: false
      )

    assert %{stats: %{samples: 3, min: 15, p50: 30, p95: 40, max: 40}} = result
  end
end
