defmodule PleromaRedux.Notifications do
  import Ecto.Query, only: [from: 2]

  alias PleromaRedux.Object
  alias PleromaRedux.Repo
  alias PleromaRedux.User

  @interactive_types ~w(Follow Like Announce)

  def list_for_user(user, opts \\ [])

  def list_for_user(%User{} = user, opts) when is_list(opts) do
    limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()
    max_id = opts |> Keyword.get(:max_id) |> normalize_id()
    since_id = opts |> Keyword.get(:since_id) |> normalize_id()

    note_ap_ids =
      from(n in Object,
        where: n.type == "Note" and n.actor == ^user.ap_id,
        select: n.ap_id
      )

    from(a in Object,
      where:
        (a.type == "Follow" and a.object == ^user.ap_id) or
          (a.type in ["Like", "Announce"] and a.object in subquery(note_ap_ids)),
      order_by: [desc: a.id],
      limit: ^limit
    )
    |> maybe_where_max_id(max_id)
    |> maybe_where_since_id(since_id)
    |> Repo.all()
  end

  def list_for_user(_user, _opts), do: []

  def interactive_types, do: @interactive_types

  defp maybe_where_max_id(query, max_id) when is_integer(max_id) and max_id > 0 do
    from(a in query, where: a.id < ^max_id)
  end

  defp maybe_where_max_id(query, _max_id), do: query

  defp maybe_where_since_id(query, since_id) when is_integer(since_id) and since_id > 0 do
    from(a in query, where: a.id > ^since_id)
  end

  defp maybe_where_since_id(query, _since_id), do: query

  defp normalize_limit(limit) when is_integer(limit) do
    limit
    |> max(1)
    |> min(40)
  end

  defp normalize_limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {int, _rest} -> normalize_limit(int)
      _ -> 20
    end
  end

  defp normalize_limit(_), do: 20

  defp normalize_id(nil), do: nil
  defp normalize_id(id) when is_integer(id) and id > 0, do: id

  defp normalize_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} when int > 0 -> int
      _ -> nil
    end
  end

  defp normalize_id(_), do: nil
end
