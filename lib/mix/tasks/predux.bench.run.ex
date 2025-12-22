defmodule Mix.Tasks.Predux.Bench.Run do
  use Mix.Task

  @shortdoc "Run a small benchmark suite against the current database"

  @moduledoc """
  Runs a small benchmark suite of common read paths (timelines, search, rendering) and
  reports timings plus Ecto query counts / total DB time.

  Recommended usage (after `mix predux.bench.seed`):

      MIX_ENV=bench mix predux.bench.run

  Options:

    * `--warmup` (default: 2)
    * `--iterations` (default: 10)
    * `--filter` (substring; optional)
  """

  @switches [warmup: :integer, iterations: :integer, filter: :string]

  @impl true
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, _args, _invalid} = OptionParser.parse(argv, switches: @switches)

    warmup = opts |> Keyword.get(:warmup, 2) |> normalize_nonneg_int()
    iterations = opts |> Keyword.get(:iterations, 10) |> normalize_pos_int()
    filter = opts |> Keyword.get(:filter) |> normalize_filter()

    cases =
      PleromaRedux.Bench.Suite.default_cases()
      |> maybe_filter_cases(filter)

    Mix.shell().info("Benchmark: warmup=#{warmup} iterations=#{iterations}")

    Enum.each(cases, fn %{name: name, fun: fun} ->
      result =
        PleromaRedux.Bench.Runner.measure(fun,
          warmup: warmup,
          iterations: iterations,
          track_queries?: true
        )

      Mix.shell().info(format_case(name, result))
    end)
  end

  defp maybe_filter_cases(cases, nil), do: cases

  defp maybe_filter_cases(cases, filter) when is_binary(filter) do
    Enum.filter(cases, fn %{name: name} -> String.contains?(name, filter) end)
  end

  defp maybe_filter_cases(cases, _filter), do: cases

  defp format_case(name, result) do
    duration = Map.fetch!(result, :stats)
    queries = Map.get(result, :queries, %{})

    duration_line =
      "  duration: avg #{format_us(duration.avg)} p50 #{format_us(duration.p50)} p95 #{format_us(duration.p95)} (min #{format_us(duration.min)} max #{format_us(duration.max)})"

    query_line =
      case queries do
        %{count: count, total_time_us: total_time} ->
          "  queries:   avg #{Float.round(count.avg, 1)} p95 #{count.p95} | db_time: avg #{format_us(total_time.avg)} p95 #{format_us(total_time.p95)}"

        _ ->
          "  queries:   (disabled)"
      end

    [name, duration_line, query_line, ""]
    |> Enum.join("\n")
  end

  defp format_us(us) when is_integer(us) do
    ms = us / 1_000
    "#{Float.round(ms, 2)}ms"
  end

  defp format_us(us) when is_float(us) do
    ms = us / 1_000
    "#{Float.round(ms, 2)}ms"
  end

  defp format_us(_), do: "n/a"

  defp normalize_filter(nil), do: nil

  defp normalize_filter(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_filter(_), do: nil

  defp normalize_nonneg_int(value) when is_integer(value) and value >= 0, do: value
  defp normalize_nonneg_int(_), do: 0

  defp normalize_pos_int(value) when is_integer(value) and value > 0, do: value
  defp normalize_pos_int(_), do: 1
end
