defmodule PleromaReduxWeb.MastodonAPI.StatusesController do
  use PleromaReduxWeb, :controller

  alias PleromaRedux.Pipeline
  alias PleromaReduxWeb.Endpoint
  alias PleromaReduxWeb.MastodonAPI.StatusRenderer

  def create(conn, %{"status" => status}) do
    status = String.trim(status || "")

    if status == "" do
      send_resp(conn, 422, "Unprocessable Entity")
    else
      user = conn.assigns.current_user

      with {:ok, object} <- Pipeline.ingest(build_note(user.ap_id, status), local: true) do
        json(conn, StatusRenderer.render_status(object, user))
      end
    end
  end

  def create(conn, _params) do
    send_resp(conn, 422, "Unprocessable Entity")
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
end
