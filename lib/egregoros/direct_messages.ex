defmodule Egregoros.DirectMessages do
  import Ecto.Query, only: [from: 2]

  alias Egregoros.Object
  alias Egregoros.Repo
  alias Egregoros.User

  @as_public "https://www.w3.org/ns/activitystreams#Public"
  @direct_message_types ~w(Note)

  def list_for_user(user, opts \\ [])

  def list_for_user(%User{ap_id: user_ap_id} = _user, opts)
      when is_binary(user_ap_id) and is_list(opts) do
    limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()
    max_id = opts |> Keyword.get(:max_id) |> normalize_id()
    since_id = opts |> Keyword.get(:since_id) |> normalize_id()

    from(o in Object,
      where:
        o.type in ^@direct_message_types and
          (o.actor == ^user_ap_id or fragment("? @> ?", o.data, ^%{"to" => [user_ap_id]}) or
             fragment("? @> ?", o.data, ^%{"cc" => [user_ap_id]}) or
             fragment("? @> ?", o.data, ^%{"bto" => [user_ap_id]}) or
             fragment("? @> ?", o.data, ^%{"bcc" => [user_ap_id]}) or
             fragment("? @> ?", o.data, ^%{"audience" => [user_ap_id]})) and
          not fragment("? @> ?", o.data, ^%{"to" => [@as_public]}) and
          not fragment("? @> ?", o.data, ^%{"cc" => [@as_public]}) and
          not fragment("? @> ?", o.data, ^%{"audience" => [@as_public]}) and
          not fragment("jsonb_exists((?->'to'), (? || '/followers'))", o.data, o.actor) and
          not fragment("jsonb_exists((?->'cc'), (? || '/followers'))", o.data, o.actor),
      order_by: [desc: o.id],
      limit: ^limit
    )
    |> maybe_where_max_id(max_id)
    |> maybe_where_since_id(since_id)
    |> Repo.all()
  end

  def list_for_user(_user, _opts), do: []

  def list_conversation(user, peer_ap_id, opts \\ [])

  def list_conversation(%User{ap_id: user_ap_id} = _user, peer_ap_id, opts)
      when is_binary(user_ap_id) and is_binary(peer_ap_id) and is_list(opts) do
    limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()
    max_id = opts |> Keyword.get(:max_id) |> normalize_id()
    since_id = opts |> Keyword.get(:since_id) |> normalize_id()
    peer_ap_id = String.trim(peer_ap_id)

    if peer_ap_id == "" do
      []
    else
      from(o in Object,
        where:
          o.type in ^@direct_message_types and
            ((o.actor == ^user_ap_id and
                (fragment("? @> ?", o.data, ^%{"to" => [peer_ap_id]}) or
                   fragment("? @> ?", o.data, ^%{"cc" => [peer_ap_id]}) or
                   fragment("? @> ?", o.data, ^%{"bto" => [peer_ap_id]}) or
                   fragment("? @> ?", o.data, ^%{"bcc" => [peer_ap_id]}) or
                   fragment("? @> ?", o.data, ^%{"audience" => [peer_ap_id]}))) or
               (o.actor == ^peer_ap_id and
                  (fragment("? @> ?", o.data, ^%{"to" => [user_ap_id]}) or
                     fragment("? @> ?", o.data, ^%{"cc" => [user_ap_id]}) or
                     fragment("? @> ?", o.data, ^%{"bto" => [user_ap_id]}) or
                     fragment("? @> ?", o.data, ^%{"bcc" => [user_ap_id]}) or
                     fragment("? @> ?", o.data, ^%{"audience" => [user_ap_id]})))) and
            not fragment("? @> ?", o.data, ^%{"to" => [@as_public]}) and
            not fragment("? @> ?", o.data, ^%{"cc" => [@as_public]}) and
            not fragment("? @> ?", o.data, ^%{"audience" => [@as_public]}) and
            not fragment("jsonb_exists((?->'to'), (? || '/followers'))", o.data, o.actor) and
            not fragment("jsonb_exists((?->'cc'), (? || '/followers'))", o.data, o.actor),
        order_by: [desc: o.id],
        limit: ^limit
      )
      |> maybe_where_max_id(max_id)
      |> maybe_where_since_id(since_id)
      |> Repo.all()
    end
  end

  def list_conversation(_user, _peer_ap_id, _opts), do: []

  def direct?(%Object{actor: actor, data: %{} = data}) when is_binary(actor) do
    to = data |> Map.get("to", []) |> List.wrap()
    cc = data |> Map.get("cc", []) |> List.wrap()
    audience = data |> Map.get("audience", []) |> List.wrap()

    followers = actor <> "/followers"

    not (@as_public in to or @as_public in cc or @as_public in audience or followers in to or
           followers in cc)
  end

  def direct?(_object), do: false

  defp maybe_where_max_id(query, max_id) when is_binary(max_id) do
    max_id = String.trim(max_id)

    if flake_id?(max_id) do
      from(o in query, where: o.id < ^max_id)
    else
      query
    end
  end

  defp maybe_where_max_id(query, _max_id), do: query

  defp maybe_where_since_id(query, since_id) when is_binary(since_id) do
    since_id = String.trim(since_id)

    if flake_id?(since_id) do
      from(o in query, where: o.id > ^since_id)
    else
      query
    end
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
end
