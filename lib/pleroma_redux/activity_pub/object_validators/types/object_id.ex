defmodule PleromaRedux.ActivityPub.ObjectValidators.Types.ObjectID do
  @moduledoc false

  use Ecto.Type

  def type, do: :string

  def cast(object) when is_binary(object) do
    object = String.trim(object)

    if object == "" do
      :error
    else
      {:ok, object}
    end
  end

  def cast(%{"id" => object}), do: cast(object)
  def cast(%{id: object}), do: cast(object)

  def cast(_), do: :error

  def dump(data), do: {:ok, data}
  def load(data), do: {:ok, data}
end

