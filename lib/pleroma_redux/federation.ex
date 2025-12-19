defmodule PleromaRedux.Federation do
  alias PleromaRedux.Activities.Follow
  alias PleromaRedux.Federation.Actor
  alias PleromaRedux.Federation.WebFinger
  alias PleromaRedux.Pipeline
  alias PleromaRedux.User

  def follow_remote(%User{} = local_user, handle) when is_binary(handle) do
    with {:ok, actor_url} <- WebFinger.lookup(handle),
         {:ok, remote_user} <- Actor.fetch_and_store(actor_url),
         {:ok, _follow} <- Pipeline.ingest(Follow.build(local_user, remote_user), local: true) do
      {:ok, remote_user}
    end
  end
end
