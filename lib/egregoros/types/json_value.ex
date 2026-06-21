defmodule Egregoros.Types.JsonValue do
  @moduledoc """
  Ecto type for JSON values that may be maps, lists, or strings.
  """

  @behaviour Ecto.Type

  @impl true
  def type, do: :map

  @impl true
  def cast(value) when is_map(value) or is_list(value) or is_binary(value), do: {:ok, value}
  def cast(nil), do: {:ok, nil}
  def cast(_value), do: :error

  @impl true
  def dump(value) when is_map(value) or is_list(value) or is_binary(value), do: {:ok, value}
  def dump(nil), do: {:ok, nil}
  def dump(_value), do: :error

  @impl true
  def load(value) when is_map(value) or is_list(value) or is_binary(value), do: {:ok, value}
  def load(nil), do: {:ok, nil}
  def load(_value), do: :error

  @impl true
  def embed_as(_format), do: :self

  @impl true
  def equal?(term1, term2), do: term1 == term2
end
