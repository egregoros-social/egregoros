defmodule EgregorosWeb.MastodonAPI.StatusesController do
  use EgregorosWeb, :controller

  alias Egregoros.Activities.Announce
  alias Egregoros.Activities.Delete
  alias Egregoros.Activities.Like
  alias Egregoros.Activities.Undo
  alias Egregoros.Media
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Publish
  alias Egregoros.Relationships
  alias Egregoros.Users
  alias EgregorosWeb.MastodonAPI.AccountRenderer
  alias EgregorosWeb.MastodonAPI.StatusRenderer

  def create(conn, %{"status" => status} = params) do
    status = String.trim(status || "")
    media_ids = Map.get(params, "media_ids", [])
    in_reply_to_id = Map.get(params, "in_reply_to_id")
    visibility = Map.get(params, "visibility", "public")
    spoiler_text = Map.get(params, "spoiler_text")
    sensitive = Map.get(params, "sensitive")
    language = Map.get(params, "language")

    if status == "" do
      send_resp(conn, 422, "Unprocessable Entity")
    else
      user = conn.assigns.current_user

      with {:ok, attachments} <- Media.attachments_from_ids(user, media_ids),
           {:ok, in_reply_to} <- resolve_in_reply_to(in_reply_to_id, user),
           {:ok, create_object} <-
             Publish.post_note(user, status,
               attachments: attachments,
               in_reply_to: in_reply_to,
               visibility: visibility,
               spoiler_text: spoiler_text,
               sensitive: sensitive,
               language: language
             ),
           %{} = object <- Objects.get_by_ap_id(create_object.object) do
        json(conn, StatusRenderer.render_status(object, user))
      else
        {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
      end
    end
  end

  def create(conn, _params) do
    send_resp(conn, 422, "Unprocessable Entity")
  end

  defp resolve_in_reply_to(nil, _user), do: {:ok, nil}
  defp resolve_in_reply_to("", _user), do: {:ok, nil}

  defp resolve_in_reply_to(in_reply_to_id, user)
       when is_binary(in_reply_to_id) and is_map(user) do
    case Objects.get(in_reply_to_id) do
      %{} = object ->
        if Objects.visible_to?(object, user) do
          {:ok, object.ap_id}
        else
          {:error, :not_found}
        end

      _ -> {:error, :not_found}
    end
  end

  defp resolve_in_reply_to(in_reply_to_id, user)
       when is_integer(in_reply_to_id) and is_map(user) do
    case Objects.get(in_reply_to_id) do
      %{} = object ->
        if Objects.visible_to?(object, user) do
          {:ok, object.ap_id}
        else
          {:error, :not_found}
        end

      _ -> {:error, :not_found}
    end
  end

  defp resolve_in_reply_to(_in_reply_to_id, _user), do: {:error, :not_found}

  def show(conn, %{"id" => id}) do
    current_user = conn.assigns[:current_user]

    case Objects.get(id) do
      nil ->
        send_resp(conn, 404, "Not Found")

      object ->
        if Objects.visible_to?(object, current_user) do
          json(conn, StatusRenderer.render_status(object, current_user))
        else
          send_resp(conn, 404, "Not Found")
        end
    end
  end

  def context(conn, %{"id" => id}) do
    current_user = conn.assigns[:current_user]

    case Objects.get(id) do
      nil ->
        send_resp(conn, 404, "Not Found")

      object ->
        if Objects.visible_to?(object, current_user) do
          ancestors =
            object
            |> Objects.thread_ancestors()
            |> Enum.filter(&Objects.visible_to?(&1, current_user))

          descendants =
            object
            |> Objects.thread_descendants()
            |> Enum.filter(&Objects.visible_to?(&1, current_user))

          json(conn, %{
            "ancestors" => StatusRenderer.render_statuses(ancestors, current_user),
            "descendants" => StatusRenderer.render_statuses(descendants, current_user)
          })
        else
          send_resp(conn, 404, "Not Found")
        end
    end
  end

  def favourited_by(conn, %{"id" => id}) do
    current_user = conn.assigns.current_user

    case Objects.get(id) do
      nil ->
        send_resp(conn, 404, "Not Found")

      object ->
        if Objects.visible_to?(object, current_user) do
          Relationships.list_by_type_object("Like", object.ap_id)
          |> Enum.map(&render_actor_account(&1.actor))
          |> then(&json(conn, &1))
        else
          send_resp(conn, 404, "Not Found")
        end
    end
  end

  def reblogged_by(conn, %{"id" => id}) do
    current_user = conn.assigns.current_user

    case Objects.get(id) do
      nil ->
        send_resp(conn, 404, "Not Found")

      object ->
        if Objects.visible_to?(object, current_user) do
          Relationships.list_by_type_object("Announce", object.ap_id)
          |> Enum.map(&render_actor_account(&1.actor))
          |> then(&json(conn, &1))
        else
          send_resp(conn, 404, "Not Found")
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    with %{} = object <- Objects.get(id),
         %{} = user <- conn.assigns.current_user,
         true <- object.type == "Note" and object.actor == user.ap_id,
         {:ok, _delete} <- Pipeline.ingest(Delete.build(user, object), local: true) do
      json(conn, StatusRenderer.render_status(object, user))
    else
      nil -> send_resp(conn, 404, "Not Found")
      false -> send_resp(conn, 403, "Forbidden")
      {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
    end
  end

  def favourite(conn, %{"id" => id}) do
    with %{} = object <- Objects.get(id),
         %{} = user <- conn.assigns.current_user,
         true <- Objects.visible_to?(object, user) do
      case Relationships.get_by_type_actor_object("Like", user.ap_id, object.ap_id) do
        %{} ->
          json(conn, StatusRenderer.render_status(object, user))

        nil ->
          with {:ok, _liked} <- Pipeline.ingest(Like.build(user, object), local: true) do
            json(conn, StatusRenderer.render_status(object, user))
          else
            {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
          end
      end
    else
      nil -> send_resp(conn, 404, "Not Found")
      false -> send_resp(conn, 404, "Not Found")
      {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
    end
  end

  def unfavourite(conn, %{"id" => id}) do
    with %{} = object <- Objects.get(id),
         %{} = user <- conn.assigns.current_user,
         true <- Objects.visible_to?(object, user),
         %{} =
           relationship <-
           Relationships.get_by_type_actor_object(
             "Like",
             user.ap_id,
             object.ap_id
           ),
         {:ok, _undo} <-
           Pipeline.ingest(Undo.build(user, relationship.activity_ap_id),
             local: true
           ) do
      json(conn, StatusRenderer.render_status(object, user))
    else
      nil -> send_resp(conn, 404, "Not Found")
      false -> send_resp(conn, 404, "Not Found")
      {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
    end
  end

  def reblog(conn, %{"id" => id}) do
    with %{} = object <- Objects.get(id),
         %{} = user <- conn.assigns.current_user,
         true <- Objects.visible_to?(object, user) do
      case Relationships.get_by_type_actor_object("Announce", user.ap_id, object.ap_id) do
        %{} = relationship ->
          relationship.activity_ap_id
          |> Objects.get_by_ap_id()
          |> case do
            %{} = announce -> json(conn, StatusRenderer.render_status(announce, user))
            _ -> json(conn, StatusRenderer.render_status(object, user))
          end

        nil ->
          with {:ok, announce} <- Pipeline.ingest(Announce.build(user, object), local: true) do
            json(conn, StatusRenderer.render_status(announce, user))
          else
            {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
          end
      end
    else
      nil -> send_resp(conn, 404, "Not Found")
      false -> send_resp(conn, 404, "Not Found")
      {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
    end
  end

  def unreblog(conn, %{"id" => id}) do
    with %{} = object <- Objects.get(id),
         %{} = user <- conn.assigns.current_user,
         true <- Objects.visible_to?(object, user),
         %{} =
           relationship <-
           Relationships.get_by_type_actor_object(
             "Announce",
             user.ap_id,
             object.ap_id
           ),
         {:ok, _undo} <-
           Pipeline.ingest(Undo.build(user, relationship.activity_ap_id),
             local: true
           ) do
      json(conn, StatusRenderer.render_status(object, user))
    else
      nil -> send_resp(conn, 404, "Not Found")
      false -> send_resp(conn, 404, "Not Found")
      {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
    end
  end

  defp render_actor_account(actor_ap_id) when is_binary(actor_ap_id) do
    actor_ap_id
    |> account_for_actor()
    |> AccountRenderer.render_account()
  end

  defp render_actor_account(_), do: AccountRenderer.render_account(nil)

  defp account_for_actor(actor_ap_id) when is_binary(actor_ap_id) do
    Users.get_by_ap_id(actor_ap_id) ||
      %{ap_id: actor_ap_id, nickname: fallback_username(actor_ap_id)}
  end

  defp account_for_actor(_), do: nil

  defp fallback_username(actor_ap_id) do
    case URI.parse(actor_ap_id) do
      %URI{path: path} when is_binary(path) and path != "" ->
        path
        |> String.split("/", trim: true)
        |> List.last()
        |> case do
          nil -> "unknown"
          value -> value
        end

      _ ->
        "unknown"
    end
  end
end
