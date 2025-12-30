defmodule Egregoros.Relays do
  import Ecto.Query, only: [from: 2]

  alias Egregoros.Activities.Follow
  alias Egregoros.Activities.Undo
  alias Egregoros.Federation.Actor
  alias Egregoros.Federation.InternalFetchActor
  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Relay
  alias Egregoros.Relationships
  alias Egregoros.Repo
  alias Egregoros.SafeURL
  alias Egregoros.Users

  def list_relays do
    from(r in Relay, order_by: [asc: r.ap_id])
    |> Repo.all()
  end

  def subscribed?(ap_id) when is_binary(ap_id) do
    ap_id = String.trim(ap_id)

    if ap_id == "" do
      false
    else
      Repo.exists?(from(r in Relay, where: r.ap_id == ^ap_id))
    end
  end

  def subscribed?(_ap_id), do: false

  def subscribe(relay_ap_id) when is_binary(relay_ap_id) do
    relay_ap_id = String.trim(relay_ap_id)

    with :ok <- SafeURL.validate_http_url(relay_ap_id),
         {:ok, relay_user} <- Actor.fetch_and_store(relay_ap_id),
         {:ok, internal} <- InternalFetchActor.get_actor(),
         {:ok, relay} <- upsert_relay(relay_user.ap_id),
         :ok <- ensure_following(internal.ap_id, relay_user.ap_id, internal, relay_user) do
      {:ok, relay}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_relay}
    end
  end

  def subscribe(_relay_ap_id), do: {:error, :invalid_relay}

  def unsubscribe(relay_id) when is_integer(relay_id) and relay_id > 0 do
    case Repo.get(Relay, relay_id) do
      %Relay{} = relay ->
        with {:ok, internal} <- InternalFetchActor.get_actor() do
          _ = undo_follow(internal.ap_id, relay.ap_id, internal)
          _ = Repo.delete(relay)
          {:ok, relay}
        end

      nil ->
        {:error, :not_found}
    end
  end

  def unsubscribe(_relay_id), do: {:error, :invalid_relay}

  def delete_by_ap_id(ap_id) when is_binary(ap_id) do
    ap_id = String.trim(ap_id)

    if ap_id == "" do
      :ok
    else
      _ = from(r in Relay, where: r.ap_id == ^ap_id) |> Repo.delete_all()
      :ok
    end
  end

  def delete_by_ap_id(_ap_id), do: :ok

  defp upsert_relay(ap_id) when is_binary(ap_id) do
    case Repo.get_by(Relay, ap_id: ap_id) do
      %Relay{} = relay ->
        {:ok, relay}

      nil ->
        %Relay{}
        |> Relay.changeset(%{ap_id: ap_id})
        |> Repo.insert()
    end
  end

  defp ensure_following(internal_ap_id, relay_ap_id, internal, relay_user)
       when is_binary(internal_ap_id) and is_binary(relay_ap_id) do
    cond do
      Relationships.get_by_type_actor_object("Follow", internal_ap_id, relay_ap_id) != nil ->
        :ok

      true ->
        case Pipeline.ingest(Follow.build(internal, relay_user), local: true) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
          _ -> {:error, :follow_failed}
        end
    end
  end

  defp undo_follow(internal_ap_id, relay_ap_id, internal)
       when is_binary(internal_ap_id) and is_binary(relay_ap_id) do
    relationship =
      Relationships.get_by_type_actor_object("Follow", internal_ap_id, relay_ap_id) ||
        Relationships.get_by_type_actor_object("FollowRequest", internal_ap_id, relay_ap_id)

    follow_ap_id =
      case relationship do
        %{activity_ap_id: ap_id} when is_binary(ap_id) -> String.trim(ap_id)
        _ -> ""
      end

    follow_object =
      if follow_ap_id == "" do
        nil
      else
        Objects.get_by_ap_id(follow_ap_id)
      end

    case follow_object do
      %Object{type: "Follow"} = object ->
        _ = Pipeline.ingest(Undo.build(internal, object), local: true)
        :ok

      _ ->
        _ = Relationships.delete_by_type_actor_object("Follow", internal_ap_id, relay_ap_id)

        _ =
          Relationships.delete_by_type_actor_object("FollowRequest", internal_ap_id, relay_ap_id)

        if follow_ap_id != "" do
          with %{} = relay_user <- Users.get_by_ap_id(relay_ap_id),
               inbox when is_binary(inbox) and inbox != "" <- relay_user.inbox do
            Egregoros.Federation.Delivery.deliver(
              internal,
              inbox,
              Undo.build(internal, follow_ap_id)
            )
          end
        end

        :ok
    end
  end
end
