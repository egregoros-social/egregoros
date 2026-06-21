defmodule Egregoros.ActivityPub.TypeNormalizer do
  @moduledoc false

  # ActivityPub allows objects to declare multiple types (array form).
  # Egregoros stores a single type in the dedicated DB column for routing/querying,
  # so we normalize multi-type inputs to a primary type for validation/dispatch,
  # while still preserving the canonical type array in the stored JSON data.

  @type type_metadata :: %{
          primary_type: String.t(),
          auxiliary_types: [String.t()],
          had_type_array?: boolean()
        }

  def normalize_incoming(%{} = activity) do
    case fetch_type(activity) do
      {:ok, type_value, key} ->
        case normalize_type_value(type_value) do
          {:ok, primary, auxiliary, had_type_array?} ->
            normalized =
              if had_type_array? do
                put_type(activity, key, primary)
              else
                activity
              end

            metadata =
              if had_type_array? do
                # TODO: We currently pick the first string type as primary, but we may need
                # smarter selection logic for multi-type objects in the future.
                %{
                  primary_type: primary,
                  auxiliary_types: auxiliary,
                  had_type_array?: true
                }
              else
                nil
              end

            {:ok, normalized, metadata}

          {:error, :invalid_type} ->
            {:error, :invalid}
        end

      :error ->
        {:ok, activity, nil}
    end
  end

  def put_type_metadata(opts, nil) when is_list(opts) do
    Keyword.delete(opts, :type_metadata)
  end

  def put_type_metadata(opts, %{} = metadata) when is_list(opts) do
    Keyword.put(opts, :type_metadata, metadata)
  end

  def primary_type(%{} = object) do
    case fetch_type(object) do
      {:ok, type_value, _key} -> primary_type(type_value)
      :error -> nil
    end
  end

  def primary_type(type) when is_binary(type) do
    if type == "", do: nil, else: type
  end

  def primary_type(type) when is_list(type) do
    type
    |> normalize_string_types()
    |> List.first()
  end

  def primary_type(_type), do: nil

  def apply_type_metadata(attrs) when is_map(attrs) do
    metadata = Map.get(attrs, :type_metadata) || Map.get(attrs, "type_metadata")

    attrs =
      attrs
      |> Map.delete(:type_metadata)
      |> Map.delete("type_metadata")

    case metadata do
      %{
        primary_type: primary,
        auxiliary_types: auxiliary,
        had_type_array?: true
      }
      when is_binary(primary) and is_list(auxiliary) ->
        # We persist auxiliary types in internal (never in `data`) to keep data canonical.
        data = Map.get(attrs, :data) || Map.get(attrs, "data")
        internal = Map.get(attrs, :internal) || Map.get(attrs, "internal") || %{}

        updated_data =
          if is_map(data) do
            data
            |> Map.delete(:type)
            |> Map.put("type", [primary | auxiliary])
          else
            data
          end

        updated_internal = Map.put(internal, "auxiliary_types", auxiliary)

        attrs
        |> put_attr(:data, updated_data)
        |> put_attr(:internal, updated_internal)

      _ ->
        attrs
    end
  end

  defp normalize_type_value(type) when is_binary(type) do
    {:ok, type, [], false}
  end

  defp normalize_type_value(type) when is_list(type) do
    types = normalize_string_types(type)

    case types do
      [] -> {:error, :invalid_type}
      [primary | auxiliary] -> {:ok, primary, auxiliary, true}
    end
  end

  defp normalize_type_value(_type), do: {:error, :invalid_type}

  defp normalize_string_types(type_list) do
    type_list
    |> Enum.filter(&is_binary/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp fetch_type(%{} = map) do
    cond do
      Map.has_key?(map, "type") -> {:ok, Map.get(map, "type"), "type"}
      Map.has_key?(map, :type) -> {:ok, Map.get(map, :type), :type}
      true -> :error
    end
  end

  defp put_type(%{} = map, "type", value) do
    map
    |> Map.delete(:type)
    |> Map.put("type", value)
  end

  defp put_type(%{} = map, :type, value) do
    map
    |> Map.delete("type")
    |> Map.put(:type, value)
  end

  defp put_attr(%{} = attrs, key, value) when is_atom(key) do
    attrs
    |> Map.delete(to_string(key))
    |> Map.put(key, value)
  end
end
