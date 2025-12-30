defmodule EgregorosWeb.Param do
  @moduledoc false

  def truthy?(value) do
    case value do
      true -> true
      1 -> true
      "1" -> true
      "true" -> true
      _ -> false
    end
  end
end
