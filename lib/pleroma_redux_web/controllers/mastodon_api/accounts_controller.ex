defmodule PleromaReduxWeb.MastodonAPI.AccountsController do
  use PleromaReduxWeb, :controller

  alias PleromaRedux.Activities.Follow
  alias PleromaRedux.Activities.Undo
  alias PleromaRedux.AvatarStorage
  alias PleromaRedux.Federation.Actor
  alias PleromaRedux.Federation.WebFinger
  alias PleromaRedux.Handles
  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Relationships
  alias PleromaRedux.Users
  alias PleromaReduxWeb.Endpoint
  alias PleromaReduxWeb.MastodonAPI.AccountRenderer
  alias PleromaReduxWeb.MastodonAPI.Pagination
  alias PleromaReduxWeb.MastodonAPI.RelationshipRenderer
  alias PleromaReduxWeb.MastodonAPI.StatusRenderer

  def verify_credentials(conn, _params) do
    json(conn, AccountRenderer.render_account(conn.assigns.current_user))
  end

  def update_credentials(conn, params) do
    user = conn.assigns.current_user

    attrs =
      %{
        name: Map.get(params, "display_name"),
        bio: Map.get(params, "note")
      }
      |> Enum.reject(fn {_k, v} -> v == nil end)
      |> Map.new(fn {k, v} -> {k, to_string(v)} end)

    with {:ok, attrs} <- maybe_put_avatar(user, params, attrs),
         {:ok, user} <- Users.update_profile(user, attrs) do
      json(conn, AccountRenderer.render_account(user))
    else
      {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
    end
  end

  def show(conn, %{"id" => id}) do
    case Users.get(id) do
      nil -> send_resp(conn, 404, "Not Found")
      user -> json(conn, AccountRenderer.render_account(user))
    end
  end

  def lookup(conn, %{"acct" => acct}) do
    acct =
      acct
      |> to_string()
      |> String.trim()
      |> String.trim_leading("@")

    if acct == "" do
      send_resp(conn, 422, "Unprocessable Entity")
    else
      case Handles.parse_acct(acct) do
        {:ok, %{nickname: nickname, domain: nil}} ->
          lookup_local(conn, nickname)

        {:ok, %{nickname: nickname, domain: domain}} ->
          if domain == local_domain() do
            lookup_local(conn, nickname)
          else
            lookup_remote(conn, nickname <> "@" <> domain)
          end

        :error ->
          send_resp(conn, 422, "Unprocessable Entity")
      end
    end
  end

  def lookup(conn, _params) do
    send_resp(conn, 422, "Unprocessable Entity")
  end

  def statuses(conn, %{"id" => id} = params) do
    case Users.get(id) do
      nil ->
        send_resp(conn, 404, "Not Found")

      user ->
        pagination = Pagination.parse(params)

        objects =
          if pinned_only?(params) do
            []
          else
            Objects.list_public_statuses_by_actor(user.ap_id,
              limit: pagination.limit + 1,
              max_id: pagination.max_id,
              since_id: pagination.since_id
            )
          end

        has_more? = length(objects) > pagination.limit
        objects = Enum.take(objects, pagination.limit)

        conn
        |> Pagination.maybe_put_links(objects, has_more?, pagination)
        |> json(StatusRenderer.render_statuses(objects))
    end
  end

  def followers(conn, %{"id" => id}) do
    case Users.get(id) do
      nil ->
        send_resp(conn, 404, "Not Found")

      user ->
        followers =
          user.ap_id
          |> Relationships.list_follows_to()
          |> Enum.map(&Users.get_by_ap_id(&1.actor))
          |> Enum.filter(&is_map/1)
          |> Enum.map(&AccountRenderer.render_account/1)

        json(conn, followers)
    end
  end

  def following(conn, %{"id" => id}) do
    case Users.get(id) do
      nil ->
        send_resp(conn, 404, "Not Found")

      user ->
        following =
          user.ap_id
          |> Relationships.list_follows_by_actor()
          |> Enum.map(&Users.get_by_ap_id(&1.object))
          |> Enum.filter(&is_map/1)
          |> Enum.map(&AccountRenderer.render_account/1)

        json(conn, following)
    end
  end

  def relationships(conn, params) do
    ids = Map.get(params, "id", [])

    relationships =
      ids
      |> List.wrap()
      |> Enum.map(&Users.get/1)
      |> Enum.filter(&is_map/1)
      |> Enum.map(&RelationshipRenderer.render_relationship(conn.assigns.current_user, &1))

    json(conn, relationships)
  end

  def follow(conn, %{"id" => id}) do
    with %{} = target <- Users.get(id),
         {:ok, _follow} <-
           Pipeline.ingest(Follow.build(conn.assigns.current_user, target),
             local: true
           ) do
      json(conn, RelationshipRenderer.render_relationship(conn.assigns.current_user, target))
    else
      nil -> send_resp(conn, 404, "Not Found")
      {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
    end
  end

  def unfollow(conn, %{"id" => id}) do
    with %{} = target <- Users.get(id),
         %{} =
           relationship <-
           Relationships.get_by_type_actor_object(
             "Follow",
             conn.assigns.current_user.ap_id,
             target.ap_id
           ),
         {:ok, _undo} <-
           Pipeline.ingest(Undo.build(conn.assigns.current_user, relationship.activity_ap_id),
             local: true
           ) do
      json(conn, RelationshipRenderer.render_relationship(conn.assigns.current_user, target))
    else
      nil -> send_resp(conn, 404, "Not Found")
      {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
    end
  end

  defp pinned_only?(params) when is_map(params) do
    case Map.get(params, "pinned") do
      true -> true
      "true" -> true
      1 -> true
      "1" -> true
      _ -> false
    end
  end

  defp lookup_local(conn, nickname) do
    case Users.get_by_nickname(nickname) do
      nil -> send_resp(conn, 404, "Not Found")
      user -> json(conn, AccountRenderer.render_account(user))
    end
  end

  defp lookup_remote(conn, handle) do
    with {:ok, actor_url} <- WebFinger.lookup(handle),
         {:ok, user} <- Actor.fetch_and_store(actor_url) do
      json(conn, AccountRenderer.render_account(user))
    else
      _ -> send_resp(conn, 404, "Not Found")
    end
  end

  defp local_domain do
    Endpoint.url()
    |> URI.parse()
    |> Map.get(:host)
  end

  defp maybe_put_avatar(user, %{"avatar" => %Plug.Upload{} = upload}, attrs) when is_map(attrs) do
    case AvatarStorage.store_avatar(user, upload) do
      {:ok, url_path} -> {:ok, Map.put(attrs, :avatar_url, url_path)}
      {:error, _} -> {:error, :invalid_avatar}
    end
  end

  defp maybe_put_avatar(_user, _params, attrs), do: {:ok, attrs}
end
