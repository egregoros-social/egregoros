defmodule EgregorosWeb.ReturnTo do
  @moduledoc false

  def safe_return_to(return_to) when is_binary(return_to) do
    return_to = String.trim(return_to)

    cond do
      return_to == "" ->
        nil

      String.starts_with?(return_to, "/") and not String.starts_with?(return_to, "//") ->
        return_to

      true ->
        nil
    end
  end

  def safe_return_to(_return_to), do: nil
end
