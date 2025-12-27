defmodule Egregoros.RateLimiter.Stub do
  @behaviour Egregoros.RateLimiter

  @impl true
  def allow?(_bucket, _key, _limit, _interval_ms), do: :ok
end

