defmodule PleromaRedux.ActivityPub.ObjectValidators.Types.DateTime do
  @moduledoc false

  use Ecto.Type

  def type, do: :string

  def cast(datetime) when is_binary(datetime) do
    with {:ok, datetime, _} <- DateTime.from_iso8601(datetime) do
      {:ok, DateTime.to_iso8601(datetime)}
    else
      {:error, :missing_offset} -> cast("#{datetime}Z")
      _ -> :error
    end
  end

  def cast(_), do: :error

  def dump(data), do: {:ok, data}
  def load(data), do: {:ok, data}
end

