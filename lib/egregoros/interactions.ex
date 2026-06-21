defmodule Egregoros.Interactions do
  @moduledoc false

  alias Egregoros.Activities.Announce
  alias Egregoros.Activities.Delete
  alias Egregoros.Activities.EmojiReact
  alias Egregoros.Activities.Like
  alias Egregoros.Activities.Undo
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Relationship
  alias Egregoros.Relationships
  alias Egregoros.User
  alias EgregorosWeb.Endpoint

  def toggle_like(%User{} = user, post_id) when is_binary(post_id) do
    with %{} = post <- Objects.get(post_id),
         true <- post.type in ["Note", "Question", "VerifiableCredential"],
         true <- Objects.visible_to?(post, user) do
      case Relationships.get_by_type_actor_object("Like", user.ap_id, post.ap_id) do
        %Relationship{} = relationship ->
          undo(user, relationship)

        nil ->
          Pipeline.ingest(Like.build(user, post), local: true)
      end
    else
      _ -> {:error, :not_found}
    end
  end

  def toggle_repost(%User{} = user, post_id) when is_binary(post_id) do
    with %{} = post <- Objects.get(post_id),
         true <- post.type in ["Note", "Question", "VerifiableCredential"],
         true <- Objects.visible_to?(post, user) do
      case Relationships.get_by_type_actor_object("Announce", user.ap_id, post.ap_id) do
        %Relationship{} = relationship ->
          undo(user, relationship)

        nil ->
          Pipeline.ingest(Announce.build(user, post), local: true)
      end
    else
      _ -> {:error, :not_found}
    end
  end

  def toggle_reaction(%User{} = user, post_id, emoji)
      when is_binary(post_id) and is_binary(emoji) do
    with %{} = post <- Objects.get(post_id),
         true <- post.type in ["Note", "Question", "VerifiableCredential"],
         true <- Objects.visible_to?(post, user) do
      relationship_type = "EmojiReact:" <> emoji

      case Relationships.get_by_type_actor_object(relationship_type, user.ap_id, post.ap_id) do
        %Relationship{} = relationship ->
          undo(user, relationship)

        nil ->
          Pipeline.ingest(EmojiReact.build(user, post, emoji), local: true)
      end
    else
      _ -> {:error, :not_found}
    end
  end

  def toggle_bookmark(%User{} = user, post_id) when is_binary(post_id) do
    with %{} = post <- Objects.get(post_id),
         true <- post.type in ["Note", "Question", "VerifiableCredential"],
         true <- Objects.visible_to?(post, user) do
      case Relationships.get_by_type_actor_object("Bookmark", user.ap_id, post.ap_id) do
        %Relationship{} ->
          _ = Relationships.delete_by_type_actor_object("Bookmark", user.ap_id, post.ap_id)
          {:ok, :unbookmarked}

        nil ->
          Relationships.upsert_relationship(%{
            type: "Bookmark",
            actor: user.ap_id,
            object: post.ap_id,
            activity_ap_id: Endpoint.url() <> "/activities/bookmark/" <> Ecto.UUID.generate()
          })
          |> case do
            {:ok, _relationship} -> {:ok, :bookmarked}
            {:error, reason} -> {:error, reason}
          end
      end
    else
      _ -> {:error, :not_found}
    end
  end

  def delete_post(%User{} = user, post_id) when is_binary(post_id) do
    with %{} = post <- Objects.get(post_id),
         true <- post.type in ["Note", "Question"],
         true <- post.local,
         true <- post.actor == user.ap_id do
      Pipeline.ingest(Delete.build(user, post), local: true)
    else
      _ -> {:error, :not_found}
    end
  end

  defp undo(%User{} = user, %Relationship{} = relationship) do
    Pipeline.ingest(Undo.build(user, relationship.activity_ap_id), local: true)
  end
end
