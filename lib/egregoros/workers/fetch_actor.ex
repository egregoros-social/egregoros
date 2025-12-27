defmodule Egregoros.Workers.FetchActor do
  use Oban.Worker,
    queue: :federation_incoming,
    max_attempts: 3,
    unique: [period: 60 * 60, keys: [:ap_id]]

  alias Egregoros.Federation.Actor
  alias Egregoros.Users

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ap_id" => ap_id}}) when is_binary(ap_id) do
    case Users.get_by_ap_id(ap_id) do
      %{} ->
        :ok

      nil ->
        case Actor.fetch_and_store(ap_id) do
          {:ok, _user} -> :ok
          {:error, reason} -> {:error, reason}
          _ -> {:error, :actor_fetch_failed}
        end
    end
  end

  def perform(%Oban.Job{}), do: {:discard, :invalid_args}
end
