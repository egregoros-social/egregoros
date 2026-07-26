defmodule Egregoros.Workers.IngestActivity do
  use Oban.Worker, queue: :federation_incoming, max_attempts: 5

  require Logger

  alias Egregoros.IngestError
  alias Egregoros.Pipeline

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"activity" => activity} = args}) when is_map(activity) do
    inbox_user_ap_id = Map.get(args, "inbox_user_ap_id")

    opts =
      [local: false]
      |> maybe_put_inbox_user_ap_id(inbox_user_ap_id)

    case Pipeline.ingest(activity, opts) do
      {:ok, _object} -> :ok
      {:error, reason} -> handle_failure(reason, activity)
    end
  end

  def perform(%Oban.Job{}), do: {:discard, :invalid_args}

  # Logs deliberately carry the activity id and type only — never the payload,
  # which can contain private content.
  defp handle_failure(reason, activity) do
    class = IngestError.classify(reason)
    known? = is_atom(reason) and reason in IngestError.known_reasons()

    cond do
      not known? ->
        Logger.warning(
          "ingest: discarding, unclassified failure reason=#{inspect(reason)} #{describe(activity)}"
        )

      class == :transient ->
        Logger.info("ingest: retrying, reason=#{inspect(reason)} #{describe(activity)}")

      true ->
        Logger.info("ingest: rejected, reason=#{inspect(reason)} #{describe(activity)}")
    end

    IngestError.outcome(class, reason)
  end

  defp describe(activity) do
    "activity_id=#{inspect(Map.get(activity, "id"))} type=#{inspect(Map.get(activity, "type"))}"
  end

  defp maybe_put_inbox_user_ap_id(opts, inbox_user_ap_id) when is_binary(inbox_user_ap_id) do
    inbox_user_ap_id = String.trim(inbox_user_ap_id)

    if inbox_user_ap_id == "",
      do: opts,
      else: Keyword.put(opts, :inbox_user_ap_id, inbox_user_ap_id)
  end

  defp maybe_put_inbox_user_ap_id(opts, _inbox_user_ap_id), do: opts
end
