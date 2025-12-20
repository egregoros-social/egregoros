defmodule PleromaRedux.ActivityPub.ObjectValidators.Types.Recipients do
  @moduledoc false

  use Ecto.Type

  alias PleromaRedux.ActivityPub.ObjectValidators.Types.ObjectID

  def type, do: {:array, ObjectID}

  def cast(nil), do: {:ok, nil}

  def cast(object) when is_binary(object) do
    cast([object])
  end

  def cast(object) when is_map(object) do
    case ObjectID.cast(object) do
      {:ok, data} -> {:ok, [data]}
      _ -> :error
    end
  end

  def cast(data) when is_list(data) do
    data =
      data
      |> Enum.reduce([], fn element, acc ->
        case ObjectID.cast(element) do
          {:ok, id} -> [id | acc]
          _ -> acc
        end
      end)
      |> Enum.sort()
      |> Enum.uniq()

    {:ok, data}
  end

  def cast(_), do: :error

  def dump(data), do: {:ok, data}
  def load(data), do: {:ok, data}
end

