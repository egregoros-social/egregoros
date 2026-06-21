defmodule Egregoros.Activities.Helpers do
  @moduledoc false

  def maybe_put(%{} = map, _key, nil), do: map
  def maybe_put(%{} = map, key, value), do: Map.put(map, key, value)
  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, key, value), do: Map.put(map, key, value)

  # Multi-type ActivityPub objects are normalized to a primary type for routing,
  # but we still need to carry metadata forward so persistence can restore the
  # canonical type array and store auxiliary types in internal state.
  def attach_type_metadata(%{} = attrs, opts) when is_list(opts) do
    case Keyword.get(opts, :type_metadata) do
      nil -> attrs
      metadata -> Map.put(attrs, :type_metadata, metadata)
    end
  end

  def attach_type_metadata(attrs, _opts), do: attrs

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
