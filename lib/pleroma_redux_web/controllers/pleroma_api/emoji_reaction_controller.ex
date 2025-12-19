defmodule PleromaReduxWeb.PleromaAPI.EmojiReactionController do
  use PleromaReduxWeb, :controller

  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaReduxWeb.Endpoint

  def create(conn, %{"id" => id, "emoji" => emoji}) do
    with %{} = object <- Objects.get(id),
         {:ok, _reaction} <-
           Pipeline.ingest(build_reaction(conn.assigns.current_user.ap_id, object.ap_id, emoji),
             local: true
           ) do
      send_resp(conn, 200, "")
    else
      nil -> send_resp(conn, 404, "Not Found")
      {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
    end
  end

  def delete(conn, %{"id" => id, "emoji" => emoji}) do
    with %{} = object <- Objects.get(id),
         %{} = reaction <- Objects.get_emoji_react(conn.assigns.current_user.ap_id, object.ap_id, emoji),
         {:ok, _undo} <-
           Pipeline.ingest(build_undo(conn.assigns.current_user.ap_id, reaction.ap_id), local: true) do
      send_resp(conn, 200, "")
    else
      nil -> send_resp(conn, 404, "Not Found")
      {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
    end
  end

  defp build_reaction(actor, object, emoji) do
    %{
      "id" => Endpoint.url() <> "/activities/react/" <> Ecto.UUID.generate(),
      "type" => "EmojiReact",
      "actor" => actor,
      "object" => object,
      "content" => emoji,
      "published" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp build_undo(actor, object) do
    %{
      "id" => Endpoint.url() <> "/activities/undo/" <> Ecto.UUID.generate(),
      "type" => "Undo",
      "actor" => actor,
      "object" => object,
      "published" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end
end
