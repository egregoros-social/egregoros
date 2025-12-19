defmodule PleromaRedux.ActivityRegistry do
  alias PleromaRedux.Activities.Accept
  alias PleromaRedux.Activities.Announce
  alias PleromaRedux.Activities.Create
  alias PleromaRedux.Activities.EmojiReact
  alias PleromaRedux.Activities.Follow
  alias PleromaRedux.Activities.Like
  alias PleromaRedux.Activities.Note
  alias PleromaRedux.Activities.Undo

  @registry %{
    "Note" => Note,
    "Create" => Create,
    "Like" => Like,
    "Announce" => Announce,
    "Follow" => Follow,
    "Accept" => Accept,
    "EmojiReact" => EmojiReact,
    "Undo" => Undo
  }

  def fetch(%{"type" => type}), do: fetch(type)

  def fetch(type) when is_binary(type) do
    case Map.fetch(@registry, type) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :unknown_type}
    end
  end
end
