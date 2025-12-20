defmodule PleromaRedux.Workers.DeliverActivity do
  use Oban.Worker, queue: :federation_outgoing, max_attempts: 10

  alias PleromaRedux.Federation.Delivery
  alias PleromaRedux.Users

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"user_id" => user_id, "inbox_url" => inbox_url, "activity" => activity}
      })
      when is_binary(inbox_url) and is_map(activity) do
    with %{} = user <- Users.get(user_id),
         {:ok, _response} <- Delivery.deliver_now(user, inbox_url, activity) do
      :ok
    else
      nil -> {:discard, :unknown_user}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :delivery_failed}
    end
  end

  def perform(%Oban.Job{}), do: {:discard, :invalid_args}
end
