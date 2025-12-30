defmodule Egregoros.Activities.Helpers do
  @moduledoc false

  def maybe_put(%{} = map, _key, nil), do: map
  def maybe_put(%{} = map, key, value), do: Map.put(map, key, value)
  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, key, value), do: Map.put(map, key, value)

  def parse_datetime(nil), do: nil
  def parse_datetime(%DateTime{} = dt), do: dt

  def parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  def parse_datetime(_value), do: nil
end
