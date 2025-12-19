defmodule PleromaRedux.Objects do
  import Ecto.Query, only: [from: 2]

  alias PleromaRedux.Object
  alias PleromaRedux.Repo

  def create_object(attrs) do
    %Object{}
    |> Object.changeset(attrs)
    |> Repo.insert()
  end

  def upsert_object(attrs) do
    case create_object(attrs) do
      {:ok, %Object{} = object} ->
        {:ok, object}

      {:error, %Ecto.Changeset{} = changeset} ->
        if unique_ap_id_error?(changeset) do
          ap_id = Map.get(attrs, :ap_id) || Map.get(attrs, "ap_id")

          case get_by_ap_id(ap_id) do
            %Object{} = object -> {:ok, object}
            _ -> {:error, changeset}
          end
        else
          {:error, changeset}
        end
    end
  end

  def get_by_ap_id(nil), do: nil
  def get_by_ap_id(ap_id) when is_binary(ap_id), do: Repo.get_by(Object, ap_id: ap_id)

  def list_notes(limit \\ 20) do
    from(o in Object, where: o.type == "Note", order_by: [desc: o.inserted_at], limit: ^limit)
    |> Repo.all()
  end

  def delete_all_notes do
    from(o in Object, where: o.type == "Note")
    |> Repo.delete_all()
  end

  defp unique_ap_id_error?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:ap_id, {_msg, opts}} -> Keyword.get(opts, :constraint) == :unique
      _ -> false
    end)
  end
end
