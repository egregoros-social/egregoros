defmodule PleromaRedux.Activities.Follow do
  alias PleromaRedux.Activities.Accept
  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.User
  alias PleromaRedux.Users
  alias PleromaReduxWeb.Endpoint

  def type, do: "Follow"

  def build(%User{ap_id: actor}, %User{ap_id: object}) do
    build(actor, object)
  end

  def build(actor, object) when is_binary(actor) and is_binary(object) do
    %{
      "id" => Endpoint.url() <> "/activities/follow/" <> Ecto.UUID.generate(),
      "type" => type(),
      "actor" => actor,
      "object" => object,
      "to" => [object],
      "published" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  def normalize(%{"type" => "Follow"} = activity), do: activity
  def normalize(_), do: nil

  def validate(%{"id" => id, "type" => "Follow", "actor" => actor, "object" => object} = activity)
      when is_binary(id) and is_binary(actor) and is_binary(object) do
    {:ok, activity}
  end

  def validate(_), do: {:error, :invalid}

  def ingest(activity, opts) do
    activity
    |> to_object_attrs(opts)
    |> Objects.upsert_object()
  end

  def side_effects(object, opts) do
    if Keyword.get(opts, :local, true) do
      deliver_follow(object)
    else
      accept_follow(object)
    end

    :ok
  end

  defp deliver_follow(object) do
    with %{} = actor <- Users.get_by_ap_id(object.actor),
         %{} = target <- Users.get_by_ap_id(object.object),
         false <- target.local do
      PleromaRedux.Federation.Delivery.deliver(actor, target.inbox, object.data)
    end
  end

  defp accept_follow(object) do
    with %{} = target <- Users.get_by_ap_id(object.object),
         true <- target.local do
      accept = Accept.build(target, object)
      _ = Pipeline.ingest(accept, local: true)
      :ok
    else
      _ -> :ok
    end
  end

  defp to_object_attrs(activity, opts) do
    %{
      ap_id: activity["id"],
      type: activity["type"],
      actor: activity["actor"],
      object: activity["object"],
      data: activity,
      published: parse_datetime(activity["published"]),
      local: Keyword.get(opts, :local, true)
    }
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: dt
end
