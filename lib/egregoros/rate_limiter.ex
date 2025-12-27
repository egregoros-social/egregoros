defmodule Egregoros.RateLimiter do
  @callback allow?(atom(), binary(), pos_integer(), pos_integer()) ::
              :ok | {:error, :rate_limited}

  def allow?(bucket, key, limit, interval_ms)
      when is_atom(bucket) and is_binary(key) and is_integer(limit) and is_integer(interval_ms) do
    impl().allow?(bucket, key, limit, interval_ms)
  end

  def allow?(_bucket, _key, _limit, _interval_ms), do: :ok

  defp impl do
    Application.get_env(:egregoros, __MODULE__, Egregoros.RateLimiter.ETS)
  end
end

