defmodule Egregoros.Notifications do
  import Ecto.Query, only: [from: 2, dynamic: 2]

  alias Egregoros.Object
  alias Egregoros.Repo
  alias Egregoros.User

  @interactive_types ~w(Follow Like Announce EmojiReact Note)
  @topic_prefix "notifications"

  def subscribe(user_ap_id) when is_binary(user_ap_id) do
    Phoenix.PubSub.subscribe(Egregoros.PubSub, topic(user_ap_id))
  end

  def broadcast(user_ap_id, %Object{} = activity) when is_binary(user_ap_id) do
    Phoenix.PubSub.broadcast(
      Egregoros.PubSub,
      topic(user_ap_id),
      {:notification_created, activity}
    )
  end

  def list_for_user(user, opts \\ [])

  def list_for_user(%User{} = user, opts) when is_list(opts) do
    limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()
    max_id = opts |> Keyword.get(:max_id) |> normalize_id()
    since_id = opts |> Keyword.get(:since_id) |> normalize_id()
    include_reactions? = opts |> Keyword.get(:include_reactions?, true) |> normalize_boolean(true)
    include_offers? = opts |> Keyword.get(:include_offers?, false) |> normalize_boolean(false)

    :telemetry.span(
      [:egregoros, :timeline, :read],
      %{name: :list_notifications, include_reactions?: include_reactions?, limit: limit},
      fn ->
        note_ap_ids =
          from(n in Object,
            where: n.type == "Note" and n.actor == ^user.ap_id,
            select: n.ap_id
          )

        interaction_types =
          if include_reactions? do
            ["Like", "Announce", "EmojiReact"]
          else
            ["Like", "Announce"]
          end

        follow_predicate =
          dynamic([a], a.type == "Follow" and a.object == ^user.ap_id and a.actor != ^user.ap_id)

        interaction_predicate =
          dynamic(
            [a],
            a.type in ^interaction_types and a.object in subquery(note_ap_ids) and
              a.actor != ^user.ap_id
          )

        mention_predicate =
          dynamic(
            [a],
            a.type == "Note" and a.actor != ^user.ap_id and
              (fragment("? @> ?", a.data, ^%{"to" => [user.ap_id]}) or
                 fragment("? @> ?", a.data, ^%{"cc" => [user.ap_id]}))
          )

        offer_predicate =
          if include_offers? do
            dynamic(
              [a],
              a.type == "Offer" and a.actor != ^user.ap_id and
                (fragment("? @> ?", a.data, ^%{"to" => [user.ap_id]}) or
                   fragment("? @> ?", a.data, ^%{"cc" => [user.ap_id]}))
            )
          else
            dynamic([_a], false)
          end

        predicate =
          dynamic(
            [a],
            ^follow_predicate or ^interaction_predicate or ^mention_predicate or ^offer_predicate
          )

        query =
          from(a in Object,
            where: ^predicate,
            order_by: [desc: a.id],
            limit: ^limit
          )
          |> maybe_where_max_id(max_id)
          |> maybe_where_since_id(since_id)

        activities =
          Repo.all(query,
            telemetry_options: [feature: :timeline, name: :list_notifications]
          )

        {activities, %{count: length(activities), name: :list_notifications}}
      end
    )
  end

  def list_for_user(_user, _opts), do: []

  def interactive_types, do: @interactive_types

  defp topic(user_ap_id) when is_binary(user_ap_id) do
    @topic_prefix <> ":" <> user_ap_id
  end

  defp maybe_where_max_id(query, max_id) when is_binary(max_id) do
    from(a in query, where: a.id < ^max_id)
  end

  defp maybe_where_max_id(query, _max_id), do: query

  defp maybe_where_since_id(query, since_id) when is_binary(since_id) do
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

  defp normalize_id(id) when is_binary(id) do
    id = String.trim(id)

    if flake_id?(id) do
      id
    else
      nil
    end
  end

  defp normalize_id(_id), do: nil

  defp flake_id?(id) when is_binary(id) do
    id = String.trim(id)

    cond do
      id == "" ->
        false

      byte_size(id) < 18 ->
        false

      true ->
        try do
          match?(<<_::128>>, FlakeId.from_string(id))
        rescue
          _ -> false
        end
    end
  end

  defp flake_id?(_id), do: false

  defp normalize_boolean(value, _default) when is_boolean(value), do: value

  defp normalize_boolean(value, default) when is_binary(value) do
    case String.trim(String.downcase(value)) do
      "true" -> true
      "false" -> false
      _ -> default
    end
  end

  defp normalize_boolean(_value, default), do: default
end
