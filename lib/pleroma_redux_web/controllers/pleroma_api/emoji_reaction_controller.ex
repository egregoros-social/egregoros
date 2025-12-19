defmodule PleromaReduxWeb.PleromaAPI.EmojiReactionController do
  use PleromaReduxWeb, :controller

  alias PleromaRedux.Activities.EmojiReact
  alias PleromaRedux.Activities.Undo
  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Relationships

  def create(conn, %{"id" => id, "emoji" => emoji}) do
    with %{} = object <- Objects.get(id),
         %{} = user <- conn.assigns.current_user do
      relationship_type = "EmojiReact:" <> to_string(emoji)

      case Relationships.get_by_type_actor_object(relationship_type, user.ap_id, object.ap_id) do
        %{} ->
          send_resp(conn, 200, "")

        nil ->
          with {:ok, _reaction} <-
                 Pipeline.ingest(EmojiReact.build(user, object, emoji),
                   local: true
                 ) do
            send_resp(conn, 200, "")
          else
            {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
          end
      end
    else
      nil -> send_resp(conn, 404, "Not Found")
      {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
    end
  end

  def delete(conn, %{"id" => id, "emoji" => emoji}) do
    with %{} = object <- Objects.get(id),
         %{} = user <- conn.assigns.current_user,
         relationship_type = "EmojiReact:" <> to_string(emoji),
         %{} =
           relationship <-
             Relationships.get_by_type_actor_object(
               relationship_type,
               user.ap_id,
               object.ap_id
             ),
         {:ok, _undo} <- Pipeline.ingest(Undo.build(user, relationship.activity_ap_id), local: true) do
      send_resp(conn, 200, "")
    else
      nil -> send_resp(conn, 404, "Not Found")
      {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
    end
  end
end
