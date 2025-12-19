defmodule PleromaRedux.Federation do
  alias PleromaRedux.Federation.Actor
  alias PleromaRedux.Federation.WebFinger
  alias PleromaRedux.Pipeline
  alias PleromaRedux.User
  alias PleromaReduxWeb.Endpoint

  def follow_remote(%User{} = local_user, handle) when is_binary(handle) do
    with {:ok, actor_url} <- WebFinger.lookup(handle),
         {:ok, remote_user} <- Actor.fetch_and_store(actor_url),
         {:ok, _follow} <- Pipeline.ingest(build_follow(local_user, remote_user), local: true) do
      {:ok, remote_user}
    end
  end

  defp build_follow(%User{} = actor, %User{} = object) do
    %{
      "id" => Endpoint.url() <> "/activities/follow/" <> Ecto.UUID.generate(),
      "type" => "Follow",
      "actor" => actor.ap_id,
      "object" => object.ap_id,
      "published" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end
end

