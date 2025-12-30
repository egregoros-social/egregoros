defmodule EgregorosWeb.PleromaAPI.EmojiReactionController do
  use EgregorosWeb, :controller

  alias Egregoros.Activities.EmojiReact
  alias Egregoros.Activities.Undo
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Relationships

  def index(conn, %{"id" => id}) do
    with %{} = object <- Objects.get(id),
         %{} = user <- conn.assigns.current_user,
         true <- Objects.visible_to?(object, user) do
      reactions =
        object.ap_id
        |> Relationships.emoji_reaction_counts()
        |> Enum.map(fn {type, _emoji_url, count} ->
          emoji = String.replace_prefix(type, "EmojiReact:", "")

          %{
            "name" => emoji,
            "count" => count,
            "me" => Relationships.get_by_type_actor_object(type, user.ap_id, object.ap_id) != nil
          }
        end)

      json(conn, reactions)
    else
      nil -> send_resp(conn, 404, "Not Found")
      false -> send_resp(conn, 404, "Not Found")
      {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
    end
  end

  def create(conn, %{"id" => id, "emoji" => emoji}) do
    with %{} = object <- Objects.get(id),
         %{} = user <- conn.assigns.current_user,
         true <- Objects.visible_to?(object, user) do
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
      false -> send_resp(conn, 404, "Not Found")
      {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
    end
  end

  def delete(conn, %{"id" => id, "emoji" => emoji}) do
    with %{} = object <- Objects.get(id),
         %{} = user <- conn.assigns.current_user,
         true <- Objects.visible_to?(object, user),
         relationship_type = "EmojiReact:" <> to_string(emoji),
         %{} =
           relationship <-
           Relationships.get_by_type_actor_object(
             relationship_type,
             user.ap_id,
             object.ap_id
           ),
         {:ok, _undo} <-
           Pipeline.ingest(Undo.build(user, relationship.activity_ap_id), local: true) do
      send_resp(conn, 200, "")
    else
      nil -> send_resp(conn, 404, "Not Found")
      false -> send_resp(conn, 404, "Not Found")
      {:error, _} -> send_resp(conn, 422, "Unprocessable Entity")
    end
  end
end
