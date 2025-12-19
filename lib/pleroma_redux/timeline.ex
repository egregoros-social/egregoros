defmodule PleromaRedux.Timeline do
  @moduledoc """
  Timeline feed backed by objects and PubSub broadcasts.
  """

  alias PleromaRedux.Activities.Create
  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.User
  alias PleromaReduxWeb.Endpoint

  @topic "timeline"

  def subscribe do
    Phoenix.PubSub.subscribe(PleromaRedux.PubSub, @topic)
  end

  def list_posts do
    Objects.list_notes()
  end

  def create_post(%User{} = user, content) when is_binary(content) do
    content = String.trim(content)

    if content == "" do
      {:error, :empty}
    else
      with {:ok, object} <- Pipeline.ingest(build_create(user, content), local: true) do
        {:ok, object}
      end
    end
  end

  def broadcast_post(object) do
    Phoenix.PubSub.broadcast(PleromaRedux.PubSub, @topic, {:post_created, object})
  end

  def reset do
    Objects.delete_all_notes()
  end

  defp build_create(user, content) do
    note = build_note(user, content)

    %{
      "id" => Endpoint.url() <> "/activities/create/" <> Ecto.UUID.generate(),
      "type" => Create.type(),
      "actor" => user.ap_id,
      "to" => note["to"],
      "cc" => note["cc"],
      "object" => note,
      "published" => note["published"]
    }
  end

  defp build_note(user, content) do
    followers = user.ap_id <> "/followers"

    %{
      "id" => Endpoint.url() <> "/objects/" <> Ecto.UUID.generate(),
      "type" => "Note",
      "attributedTo" => user.ap_id,
      "to" => ["https://www.w3.org/ns/activitystreams#Public"],
      "cc" => [followers],
      "content" => content,
      "published" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end
end
