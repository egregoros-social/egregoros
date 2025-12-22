defmodule PleromaRedux.Federation.InternalFetchActor do
  alias PleromaRedux.Users

  @nickname "internal.fetch"
  @cache_key {__MODULE__, :actor}

  def get_actor do
    case :persistent_term.get(@cache_key, :undefined) do
      %{} = actor ->
        {:ok, actor}

      :undefined ->
        init_actor()
    end
  end

  defp init_actor do
    :global.trans({__MODULE__, :init_actor}, fn ->
      case :persistent_term.get(@cache_key, :undefined) do
        %{} = actor ->
          {:ok, actor}

        :undefined ->
          with {:ok, actor} <- Users.get_or_create_local_user(@nickname) do
            :persistent_term.put(@cache_key, actor)
            {:ok, actor}
          end
      end
    end)
  end
end
