defmodule PleromaRedux.Timeline do
  @moduledoc """
  Timeline feed backed by objects and PubSub broadcasts.
  """

  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Users
  alias PleromaReduxWeb.Endpoint

  @topic "timeline"

  def subscribe do
    Phoenix.PubSub.subscribe(PleromaRedux.PubSub, @topic)
  end

  def list_posts do
    Objects.list_notes()
  end

  def create_post(content) when is_binary(content) do
    content = String.trim(content)

    if content == "" do
      {:error, :empty}
    else
      with {:ok, user} <- Users.get_or_create_local_user("local"),
           {:ok, object} <- Pipeline.ingest(build_note(user, content), local: true) do
        Phoenix.PubSub.broadcast(PleromaRedux.PubSub, @topic, {:post_created, object})
        {:ok, object}
      end
    end
  end

  def reset do
    Objects.delete_all_notes()
  end

  defp build_note(user, content) do
    %{
      "id" => Endpoint.url() <> "/objects/" <> Ecto.UUID.generate(),
      "type" => "Note",
      "attributedTo" => user.ap_id,
      "content" => content,
      "published" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end
end
