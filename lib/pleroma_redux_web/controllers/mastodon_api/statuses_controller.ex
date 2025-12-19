defmodule PleromaReduxWeb.MastodonAPI.StatusesController do
  use PleromaReduxWeb, :controller

  alias PleromaRedux.Activities.Announce
  alias PleromaRedux.Activities.Like
  alias PleromaRedux.Activities.Undo
  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Publish
  alias PleromaReduxWeb.MastodonAPI.StatusRenderer

  def create(conn, %{"status" => status}) do
    status = String.trim(status || "")

    if status == "" do
      send_resp(conn, 422, "Unprocessable Entity")
    else
      user = conn.assigns.current_user

      with {:ok, create_object} <- Publish.post_note(user, status),
           %{} = object <- Objects.get_by_ap_id(create_object.object) do
        json(conn, StatusRenderer.render_status(object, user))
      end
    end
  end

  def create(conn, _params) do
    send_resp(conn, 422, "Unprocessable Entity")
  end

  def show(conn, %{"id" => id}) do
    case Objects.get(id) do
      nil ->
        send_resp(conn, 404, "Not Found")

      object ->
        json(conn, StatusRenderer.render_status(object))
    end
  end

  def favourite(conn, %{"id" => id}) do
    with %{} = object <- Objects.get(id),
         {:ok, _liked} <-
           Pipeline.ingest(Like.build(conn.assigns.current_user, object), local: true) do
      json(conn, StatusRenderer.render_status(object, conn.assigns.current_user))
    else
      nil -> send_resp(conn, 404, "Not Found")
      {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
    end
  end

  def unfavourite(conn, %{"id" => id}) do
    with %{} = object <- Objects.get(id),
         %{} = like <- Objects.get_by_type_actor_object("Like", conn.assigns.current_user.ap_id, object.ap_id),
         {:ok, _undo} <- Pipeline.ingest(Undo.build(conn.assigns.current_user, like), local: true) do
      json(conn, StatusRenderer.render_status(object, conn.assigns.current_user))
    else
      nil -> send_resp(conn, 404, "Not Found")
      {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
    end
  end

  def reblog(conn, %{"id" => id}) do
    with %{} = object <- Objects.get(id),
         {:ok, _announce} <- Pipeline.ingest(Announce.build(conn.assigns.current_user, object), local: true) do
      json(conn, StatusRenderer.render_status(object, conn.assigns.current_user))
    else
      nil -> send_resp(conn, 404, "Not Found")
      {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
    end
  end

  def unreblog(conn, %{"id" => id}) do
    with %{} = object <- Objects.get(id),
         %{} = announce <- Objects.get_by_type_actor_object("Announce", conn.assigns.current_user.ap_id, object.ap_id),
         {:ok, _undo} <- Pipeline.ingest(Undo.build(conn.assigns.current_user, announce), local: true) do
      json(conn, StatusRenderer.render_status(object, conn.assigns.current_user))
    else
      nil -> send_resp(conn, 404, "Not Found")
      {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
    end
  end
end
