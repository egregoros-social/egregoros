defmodule PleromaRedux.ActivityRegistry do
  @prefix "Elixir.PleromaRedux.Activities."

  def fetch(%{"type" => type}), do: fetch(type)

  def fetch(type) when is_binary(type) do
    case Map.fetch(registry(), type) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :unknown_type}
    end
  end

  defp registry do
    case :application.get_key(:pleroma_redux, :modules) do
      {:ok, modules} -> build_registry(modules)
      _ -> %{}
    end
  end

  defp build_registry(modules) when is_list(modules) do
    modules
    |> Enum.filter(&activity_module?/1)
    |> Enum.reduce(%{}, fn module, acc ->
      _ = Code.ensure_loaded?(module)

      if function_exported?(module, :type, 0) do
        Map.put(acc, module.type(), module)
      else
        acc
      end
    end)
  end

  defp activity_module?(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.starts_with?(@prefix)
  end
end
