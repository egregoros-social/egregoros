defmodule Egregoros.Pipeline do
  alias Egregoros.ActivityRegistry
  alias Egregoros.ActivityPub.TypeNormalizer
  alias Egregoros.Domain
  alias Egregoros.Federation.ActorDiscovery
  alias EgregorosWeb.Endpoint

  def ingest(activity, opts \\ []) when is_map(activity) do
    # Normalize multi-type objects before routing so ActivityRegistry and validations
    # can operate on a single primary type (the canonical multi-type array is restored
    # later when we persist data).
    with {:ok, normalized_activity, type_metadata} <- TypeNormalizer.normalize_incoming(activity),
         opts <- TypeNormalizer.put_type_metadata(opts, type_metadata),
         :ok <- validate_namespace(normalized_activity, opts),
         {:ok, module} <- ActivityRegistry.fetch(normalized_activity) do
      ingest_with(module, normalized_activity, opts)
    end
  end

  @doc false
  def ingest_with(module, activity, opts \\ [])
      when is_atom(module) and is_map(activity) and is_list(opts) do
    with {:ok, validated} <- cast_and_validate(module, activity, opts),
         :ok <- discover_actors(validated, opts),
         {:ok, object} <- module.ingest(validated, opts),
         :ok <- module.side_effects(object, opts) do
      {:ok, object}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid}
    end
  end

  defp discover_actors(activity, opts) when is_map(activity) and is_list(opts) do
    _ = ActorDiscovery.enqueue(activity, opts)
    :ok
  end

  defp cast_and_validate(module, activity, opts) do
    # Prefer cast_and_validate/2 if available (allows passing opts for inbox targeting)
    # Fall back to cast_and_validate/1 for backwards compatibility
    result =
      cond do
        function_exported?(module, :cast_and_validate, 2) ->
          module.cast_and_validate(activity, opts)

        function_exported?(module, :cast_and_validate, 1) ->
          module.cast_and_validate(activity)

        true ->
          {:error, :invalid}
      end

    case result do
      {:ok, validated} when is_map(validated) -> {:ok, validated}
      {:error, %Ecto.Changeset{}} -> {:error, :invalid}
      {:error, _} = error -> error
      _ -> {:error, :invalid}
    end
  end

  defp validate_namespace(activity, opts) when is_map(activity) and is_list(opts) do
    if Keyword.get(opts, :local, true) do
      :ok
    else
      case extract_id(activity) do
        id when is_binary(id) and id != "" ->
          if local_ap_id?(id), do: {:error, :local_id}, else: :ok

        _ ->
          :ok
      end
    end
  end

  defp validate_namespace(_activity, _opts), do: :ok

  defp extract_id(%{"id" => id}) when is_binary(id), do: id
  defp extract_id(%{id: id}) when is_binary(id), do: id
  defp extract_id(_activity), do: nil

  defp local_ap_id?(id) when is_binary(id) do
    local_domain =
      Endpoint.url()
      |> URI.parse()
      |> Domain.from_uri()

    case URI.parse(id) do
      %URI{} = uri ->
        case Domain.from_uri(uri) do
          domain when is_binary(local_domain) and is_binary(domain) and domain == local_domain ->
            true

          _ ->
            false
        end

      _ ->
        false
    end
  end
end
