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

  def delete_object(%Object{} = object) do
    Repo.delete(object)
  end

  def get(id) when is_integer(id), do: Repo.get(Object, id)

  def get(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> Repo.get(Object, int)
      _ -> nil
    end
  end

  def get_by_type_actor_object(type, actor, object)
      when is_binary(type) and is_binary(actor) and is_binary(object) do
    Repo.get_by(Object, type: type, actor: actor, object: object)
  end

  def get_emoji_react(actor, object, emoji)
      when is_binary(actor) and is_binary(object) and is_binary(emoji) do
    from(o in Object,
      where:
        o.type == "EmojiReact" and o.actor == ^actor and o.object == ^object and
          fragment("?->>'content' = ?", o.data, ^emoji),
      order_by: [desc: o.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  def list_follows_to(object_ap_id) when is_binary(object_ap_id) do
    from(o in Object, where: o.type == "Follow" and o.object == ^object_ap_id)
    |> Repo.all()
  end

  def list_follows_by_actor(actor_ap_id) when is_binary(actor_ap_id) do
    from(o in Object, where: o.type == "Follow" and o.actor == ^actor_ap_id)
    |> Repo.all()
  end

  def list_notes(limit \\ 20) do
    from(o in Object, where: o.type == "Note", order_by: [desc: o.inserted_at], limit: ^limit)
    |> Repo.all()
  end

  def list_home_notes(actor_ap_id, limit \\ 20) when is_binary(actor_ap_id) do
    followed_actor_ids =
      actor_ap_id
      |> list_follows_by_actor()
      |> Enum.map(& &1.object)
      |> Enum.filter(&is_binary/1)

    actor_ids = Enum.uniq([actor_ap_id | followed_actor_ids])

    from(o in Object,
      where: o.type == "Note" and o.actor in ^actor_ids,
      order_by: [desc: o.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  def list_notes_by_actor(actor, limit \\ 20) when is_binary(actor) do
    from(o in Object,
      where: o.type == "Note" and o.actor == ^actor,
      order_by: [desc: o.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  def count_notes_by_actor(actor) when is_binary(actor) do
    from(o in Object, where: o.type == "Note" and o.actor == ^actor)
    |> Repo.aggregate(:count, :id)
  end

  def count_by_type_object(type, object_ap_id) when is_binary(type) and is_binary(object_ap_id) do
    from(o in Object, where: o.type == ^type and o.object == ^object_ap_id)
    |> Repo.aggregate(:count, :id)
  end

  def list_creates_by_actor(actor, limit \\ 20) when is_binary(actor) do
    from(o in Object,
      where: o.type == "Create" and o.actor == ^actor,
      order_by: [desc: o.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  def count_creates_by_actor(actor) when is_binary(actor) do
    from(o in Object, where: o.type == "Create" and o.actor == ^actor)
    |> Repo.aggregate(:count, :id)
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
