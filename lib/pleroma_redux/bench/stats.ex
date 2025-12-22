defmodule PleromaRedux.Bench.Stats do
  @moduledoc false

  def summary(samples) when is_list(samples) do
    samples = Enum.filter(samples, &is_integer/1)

    case samples do
      [] ->
        raise ArgumentError, "expected a non-empty list of integer samples"

      _ ->
        sorted = Enum.sort(samples)
        count = length(sorted)

        min = List.first(sorted)
        max = List.last(sorted)

        %{
          samples: count,
          min: min,
          p50: percentile(sorted, 0.50),
          p95: percentile(sorted, 0.95),
          max: max,
          avg: Enum.sum(sorted) / count
        }
    end
  end

  defp percentile(sorted, p) when is_list(sorted) and is_float(p) and p >= 0.0 and p <= 1.0 do
    n = length(sorted)
    idx = trunc(Float.ceil(p * n)) - 1
    Enum.at(sorted, max(idx, 0))
  end
end
