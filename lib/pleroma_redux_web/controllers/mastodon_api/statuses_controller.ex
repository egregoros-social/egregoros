defmodule PleromaReduxWeb.MastodonAPI.StatusesController do
  use PleromaReduxWeb, :controller

  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaReduxWeb.Endpoint
  alias PleromaReduxWeb.MastodonAPI.StatusRenderer

  def create(conn, %{"status" => status}) do
    status = String.trim(status || "")

    if status == "" do
      send_resp(conn, 422, "Unprocessable Entity")
    else
      user = conn.assigns.current_user

      note = build_note(user.ap_id, status)
      create = build_create(user.ap_id, note)

      with {:ok, _create} <- Pipeline.ingest(create, local: true),
           %{} = object <- Objects.get_by_ap_id(note["id"]) do
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
           Pipeline.ingest(build_activity("Like", conn.assigns.current_user.ap_id, object.ap_id), local: true) do
      json(conn, StatusRenderer.render_status(object, conn.assigns.current_user))
    else
      nil -> send_resp(conn, 404, "Not Found")
      {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
    end
  end

  def unfavourite(conn, %{"id" => id}) do
    with %{} = object <- Objects.get(id),
         %{} = like <- Objects.get_by_type_actor_object("Like", conn.assigns.current_user.ap_id, object.ap_id),
         {:ok, _undo} <- Pipeline.ingest(build_activity("Undo", conn.assigns.current_user.ap_id, like.ap_id), local: true) do
      json(conn, StatusRenderer.render_status(object, conn.assigns.current_user))
    else
      nil -> send_resp(conn, 404, "Not Found")
      {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
    end
  end

  def reblog(conn, %{"id" => id}) do
    with %{} = object <- Objects.get(id),
         {:ok, _announce} <- Pipeline.ingest(build_activity("Announce", conn.assigns.current_user.ap_id, object.ap_id), local: true) do
      json(conn, StatusRenderer.render_status(object, conn.assigns.current_user))
    else
      nil -> send_resp(conn, 404, "Not Found")
      {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
    end
  end

  def unreblog(conn, %{"id" => id}) do
    with %{} = object <- Objects.get(id),
         %{} = announce <- Objects.get_by_type_actor_object("Announce", conn.assigns.current_user.ap_id, object.ap_id),
         {:ok, _undo} <- Pipeline.ingest(build_activity("Undo", conn.assigns.current_user.ap_id, announce.ap_id), local: true) do
      json(conn, StatusRenderer.render_status(object, conn.assigns.current_user))
    else
      nil -> send_resp(conn, 404, "Not Found")
      {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
    end
  end

  defp build_note(actor, content) do
    %{
      "id" => Endpoint.url() <> "/objects/" <> Ecto.UUID.generate(),
      "type" => "Note",
      "actor" => actor,
      "content" => content,
      "published" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp build_create(actor, note) do
    %{
      "id" => Endpoint.url() <> "/activities/create/" <> Ecto.UUID.generate(),
      "type" => "Create",
      "actor" => actor,
      "object" => note,
      "published" => note["published"]
    }
  end

  defp build_activity(type, actor, object) do
    %{
      "id" => Endpoint.url() <> "/activities/" <> String.downcase(type) <> "/" <> Ecto.UUID.generate(),
      "type" => type,
      "actor" => actor,
      "object" => object,
      "published" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end
end
