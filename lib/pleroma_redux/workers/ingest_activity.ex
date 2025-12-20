defmodule PleromaRedux.Workers.IngestActivity do
  use Oban.Worker, queue: :federation_incoming, max_attempts: 5

  alias PleromaRedux.Pipeline

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"activity" => activity}}) when is_map(activity) do
    case Pipeline.ingest(activity, local: false) do
      {:ok, _object} -> :ok
      {:error, reason} -> {:discard, reason}
    end
  end

  def perform(%Oban.Job{}), do: {:discard, :invalid_args}
end
