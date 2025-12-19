defmodule PleromaReduxWeb.PleromaAPI.EmojiReactionController do
  use PleromaReduxWeb, :controller

  alias PleromaRedux.Activities.EmojiReact
  alias PleromaRedux.Activities.Undo
  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline

  def create(conn, %{"id" => id, "emoji" => emoji}) do
    with %{} = object <- Objects.get(id),
         {:ok, _reaction} <-
           Pipeline.ingest(EmojiReact.build(conn.assigns.current_user, object, emoji),
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
         {:ok, _undo} <- Pipeline.ingest(Undo.build(conn.assigns.current_user, reaction), local: true) do
      send_resp(conn, 200, "")
    else
      nil -> send_resp(conn, 404, "Not Found")
      {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
    end
  end
end
