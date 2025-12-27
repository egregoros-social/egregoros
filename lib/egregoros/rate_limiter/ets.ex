defmodule Egregoros.RateLimiter.ETS do
  use GenServer

  @behaviour Egregoros.RateLimiter

  @table :egregoros_rate_limiter
  @cleanup_interval_ms 60_000
  @default_entry_ttl_ms 600_000

  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(opts) do
    _ = ensure_table()
    schedule_cleanup()
    {:ok, %{entry_ttl_ms: entry_ttl_ms(opts)}}
  end

  @impl Egregoros.RateLimiter
  def allow?(bucket, key, limit, interval_ms)
      when is_atom(bucket) and is_binary(key) and is_integer(limit) and is_integer(interval_ms) do
    bucket = bucket
    key = key |> String.trim()

    cond do
      key == "" ->
        :ok

      limit < 1 ->
        :ok

      interval_ms < 1 ->
        :ok

      true ->
        now_ms = System.monotonic_time(:millisecond)
        window_id = div(now_ms, interval_ms)
        ets_key = {bucket, key, interval_ms}

        {new_count, last_seen_ms} = bump_counter(ets_key, window_id, now_ms)

        if new_count <= limit and is_integer(last_seen_ms) do
          :ok
        else
          {:error, :rate_limited}
        end
    end
  end

  def allow?(_bucket, _key, _limit, _interval_ms), do: :ok

  @impl GenServer
  def handle_info(:cleanup, %{entry_ttl_ms: ttl_ms} = state) do
    threshold_ms = System.monotonic_time(:millisecond) - ttl_ms
    _ = cleanup_old_entries(threshold_ms)
    schedule_cleanup()
    {:noreply, state}
  end

  defp bump_counter(ets_key, window_id, now_ms) do
    case :ets.lookup(@table, ets_key) do
      [{^ets_key, ^window_id, count, _last_seen_ms}] when is_integer(count) ->
        new_count = count + 1
        :ets.insert(@table, {ets_key, window_id, new_count, now_ms})
        {new_count, now_ms}

      [{^ets_key, _old_window_id, _count, _last_seen_ms}] ->
        :ets.insert(@table, {ets_key, window_id, 1, now_ms})
        {1, now_ms}

      [] ->
        :ets.insert(@table, {ets_key, window_id, 1, now_ms})
        {1, now_ms}
    end
  end

  defp cleanup_old_entries(threshold_ms) when is_integer(threshold_ms) do
    match_spec = [
      {
        {:"$1", :"$2", :"$3", :"$4"},
        [{:<, :"$4", threshold_ms}],
        [true]
      }
    ]

    :ets.select_delete(@table, match_spec)
  end

  defp entry_ttl_ms(opts) when is_list(opts) do
    case Keyword.get(opts, :entry_ttl_ms, @default_entry_ttl_ms) do
      ttl when is_integer(ttl) and ttl >= 0 -> ttl
      _ -> @default_entry_ttl_ms
    end
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [
          :named_table,
          :public,
          :set,
          read_concurrency: true,
          write_concurrency: true
        ])

      _tid ->
        @table
    end
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end
end

