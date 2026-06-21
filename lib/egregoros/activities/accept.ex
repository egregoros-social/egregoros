defmodule Egregoros.Activities.Accept do
  use Ecto.Schema

  import Ecto.Changeset

  require Logger

  alias Egregoros.Activities.Helpers
  alias Egregoros.Activities.Update
  alias Egregoros.Pipeline
  alias Egregoros.ActivityPub.TypeNormalizer
  alias Egregoros.ActivityPub.ObjectValidators.Types.ObjectID
  alias Egregoros.ActivityPub.ObjectValidators.Types.Recipients
  alias Egregoros.ActivityPub.ObjectValidators.Types.DateTime, as: APDateTime
  alias Egregoros.Federation.Delivery
  alias Egregoros.InboxTargeting
  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Relationships
  alias Egregoros.User
  alias Egregoros.Users
  alias Egregoros.VerifiableCredentials.DataIntegrity
  alias Egregoros.VerifiableCredentials.DidWeb
  alias Egregoros.Workers.RefreshRemoteFollowingGraph
  alias EgregorosWeb.Endpoint

  def type, do: "Accept"

  @primary_key false
  embedded_schema do
    field :id, ObjectID
    field :type, :string
    field :actor, ObjectID
    field :object, ObjectID
    field :embedded_object, :map
    field :to, Recipients
    field :cc, Recipients
    field :published, APDateTime
  end

  def cast_and_validate(activity) when is_map(activity) do
    cast_activity = maybe_embed_object(activity)

    changeset =
      %__MODULE__{}
      |> cast(cast_activity, __schema__(:fields))
      |> validate_required([:id, :type, :actor, :object])
      |> validate_inclusion(:type, [type()])

    case apply_action(changeset, :insert) do
      {:ok, %__MODULE__{} = accept} -> {:ok, apply_accept(activity, accept)}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

  def ingest(activity, opts) do
    with :ok <- validate_inbox_target(activity, opts) do
      activity
      |> to_object_attrs(opts)
      |> Objects.upsert_object()
    end
  end

  def side_effects(object, opts) do
    _ = apply_follow_accept(object)
    _ = apply_offer_accept(object)
    _ = maybe_publicize_offer_credential(object)

    if Keyword.get(opts, :local, true) do
      deliver_accept(object)
    end

    :ok
  end

  defp apply_follow_accept(%Object{} = accept_object) do
    follow_object =
      case accept_object.object do
        follow_ap_id when is_binary(follow_ap_id) ->
          Objects.get_by_ap_id(follow_ap_id)

        _ ->
          nil
      end

    follow_data =
      cond do
        match?(%Object{type: "Follow"}, follow_object) ->
          follow_object.data

        is_map(accept_object.data["object"]) ->
          accept_object.data["object"]

        true ->
          nil
      end

    case follow_data do
      %{"type" => "Follow", "actor" => actor, "object" => target} ->
        actor_ap_id = extract_id(actor)
        target_ap_id = extract_id(target)

        activity_ap_id =
          case follow_object do
            %Object{type: "Follow"} = stored_follow -> stored_follow.ap_id
            _ -> Map.get(follow_data, "id")
          end

        if is_binary(actor_ap_id) and actor_ap_id != "" and is_binary(target_ap_id) and
             target_ap_id != "" do
          _ =
            Relationships.upsert_relationship(%{
              type: "Follow",
              actor: actor_ap_id,
              object: target_ap_id,
              activity_ap_id: activity_ap_id
            })

          _ =
            Relationships.delete_by_type_actor_object("FollowRequest", actor_ap_id, target_ap_id)

          _ = maybe_refresh_remote_following_graph(target_ap_id)
        end

        :ok

      _ ->
        :ok
    end
  end

  defp apply_offer_accept(%Object{} = accept_object) do
    offer_ap_id = offer_ap_id_from_accept(accept_object)
    recipient_ap_id = accept_object.actor |> normalize_ap_id()

    with offer_ap_id when is_binary(offer_ap_id) <- offer_ap_id,
         recipient_ap_id when is_binary(recipient_ap_id) <- recipient_ap_id do
      _ = Relationships.delete_by_type_actor_object("OfferPending", recipient_ap_id, offer_ap_id)

      _ =
        Relationships.upsert_relationship(%{
          type: "OfferAccepted",
          actor: recipient_ap_id,
          object: offer_ap_id,
          activity_ap_id: offer_ap_id
        })

      :ok
    else
      _ -> :ok
    end
  end

  defp offer_ap_id_from_accept(%Object{} = accept_object) do
    embedded_offer =
      case accept_object.data do
        %{"object" => %{} = offer} -> offer
        _ -> nil
      end

    embedded_offer_id =
      if is_map(embedded_offer) and TypeNormalizer.primary_type(embedded_offer) == "Offer" do
        extract_id(embedded_offer)
      else
        nil
      end

    offer_ap_id_from_object(embedded_offer_id) || offer_ap_id_from_object(accept_object.object)
  end

  defp offer_ap_id_from_accept(_accept_object), do: nil

  defp offer_ap_id_from_object(offer_ap_id) when is_binary(offer_ap_id) do
    offer_ap_id = String.trim(offer_ap_id)

    if offer_ap_id == "" do
      nil
    else
      case Objects.get_by_ap_id(offer_ap_id) do
        %Object{type: "Offer"} -> offer_ap_id
        _ -> nil
      end
    end
  end

  defp offer_ap_id_from_object(_offer_ap_id), do: nil

  defp maybe_publicize_offer_credential(%Object{} = accept_object) do
    offer_ap_id = offer_ap_id_from_accept(accept_object)

    with offer_ap_id when is_binary(offer_ap_id) <- offer_ap_id,
         %Object{type: "Offer"} = offer <- Objects.get_by_ap_id(offer_ap_id),
         %Object{} = credential <- credential_object_from_offer(offer),
         "VerifiableCredential" <- TypeNormalizer.primary_type(credential.data),
         {:ok, updated_to, added_public?} <- publicize_recipients(credential.data),
         true <- added_public?,
         %User{local: true} = issuer <- Users.get_by_ap_id(credential.actor) do
      updated_data =
        credential.data
        |> Map.put("to", updated_to)
        |> maybe_attach_credential_proof(issuer)

      attrs = %{
        ap_id: credential.ap_id,
        type: credential.type,
        actor: credential.actor,
        object: credential.object,
        data: updated_data,
        published: credential.published,
        local: credential.local,
        internal: credential.internal
      }

      case Objects.upsert_object(attrs, conflict: :replace) do
        {:ok, _updated_credential} ->
          _ = Pipeline.ingest(Update.build(issuer, updated_data), local: true)
          :ok

        _ ->
          :ok
      end
    else
      _ -> :ok
    end
  end

  defp maybe_publicize_offer_credential(_accept_object), do: :ok

  defp maybe_attach_credential_proof(%{} = credential_data, %User{} = issuer) do
    if Map.has_key?(credential_data, "proof") or Map.has_key?(credential_data, :proof) do
      credential_data
    else
      issuer_id =
        case credential_data do
          %{"issuer" => %{"id" => id}} when is_binary(id) -> id
          %{"issuer" => id} when is_binary(id) -> id
          %{issuer: %{id: id}} when is_binary(id) -> id
          %{issuer: id} when is_binary(id) -> id
          _ -> issuer.ap_id
        end

      verification_method =
        DidWeb.verification_method_id(issuer_id) || issuer.ap_id <> "#ed25519-key"

      case DataIntegrity.attach_proof(credential_data, issuer.ed25519_private_key, %{
             "verificationMethod" => verification_method,
             "proofPurpose" => "assertionMethod"
           }) do
        {:ok, signed} ->
          signed

        {:error, reason} ->
          Logger.warning("failed to attach VC proof for #{issuer.ap_id}: #{inspect(reason)}")

          credential_data
      end
    end
  end

  defp maybe_attach_credential_proof(credential_data, _issuer), do: credential_data

  defp credential_object_from_offer(%Object{data: %{"object" => %{} = embedded}}) do
    credential_id = Map.get(embedded, "id") || Map.get(embedded, :id)

    if is_binary(credential_id) and credential_id != "" do
      Objects.get_by_ap_id(credential_id)
    else
      nil
    end
  end

  defp credential_object_from_offer(%Object{object: credential_ap_id})
       when is_binary(credential_ap_id) do
    Objects.get_by_ap_id(credential_ap_id)
  end

  defp credential_object_from_offer(_offer), do: nil

  defp publicize_recipients(%{} = credential_data) do
    public = "https://www.w3.org/ns/activitystreams#Public"

    existing_to =
      credential_data
      |> Map.get("to", [])
      |> List.wrap()
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    updated_to =
      (existing_to ++ [public])
      |> Enum.uniq()

    added_public? = public not in existing_to

    {:ok, updated_to, added_public?}
  end

  defp publicize_recipients(_credential_data), do: {:error, :invalid}

  defp extract_id(%{"id" => id}) when is_binary(id), do: id
  defp extract_id(id) when is_binary(id), do: id
  defp extract_id(_), do: nil

  defp maybe_refresh_remote_following_graph(target_ap_id) when is_binary(target_ap_id) do
    target_ap_id = String.trim(target_ap_id)

    if target_ap_id == "" do
      :ok
    else
      case Users.get_by_ap_id(target_ap_id) do
        %User{local: false} ->
          _ = Oban.insert(RefreshRemoteFollowingGraph.new(%{"ap_id" => target_ap_id}))
          :ok

        _ ->
          :ok
      end
    end
  end

  defp maybe_refresh_remote_following_graph(_target_ap_id), do: :ok

  defp validate_inbox_target(%{} = activity, opts) when is_list(opts) do
    InboxTargeting.validate(opts, fn inbox_user_ap_id ->
      cond do
        InboxTargeting.addressed_to?(activity, inbox_user_ap_id) ->
          :ok

        accepted_follower_ap_id(activity) == inbox_user_ap_id ->
          :ok

        true ->
          {:error, :not_targeted}
      end
    end)
  end

  defp validate_inbox_target(_activity, _opts), do: :ok

  defp accepted_follower_ap_id(%{"object" => %{} = follow}) do
    follow
    |> Map.get("actor")
    |> normalize_ap_id()
  end

  defp accepted_follower_ap_id(%{"object" => object_id}) when is_binary(object_id) do
    case Objects.get_by_ap_id(object_id) do
      %Object{actor: actor} -> normalize_ap_id(actor)
      _ -> nil
    end
  end

  defp accepted_follower_ap_id(_activity), do: nil

  defp normalize_ap_id(nil), do: nil

  defp normalize_ap_id(ap_id) when is_binary(ap_id) do
    ap_id
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def build(%User{} = actor, %Object{type: "Follow"} = follow_object) do
    %{
      "id" => Endpoint.url() <> "/activities/accept/" <> Ecto.UUID.generate(),
      "type" => type(),
      "actor" => actor.ap_id,
      "object" => follow_object.data,
      "published" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  def build(%User{} = actor, %Object{type: "Offer"} = offer_object) do
    %{
      "id" => Endpoint.url() <> "/activities/accept/" <> Ecto.UUID.generate(),
      "type" => type(),
      "actor" => actor.ap_id,
      "object" => offer_object.data,
      "published" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp deliver_accept(%Object{} = accept_object) do
    with %{} = actor <- Users.get_by_ap_id(accept_object.actor),
         %{} = target <- accepted_target(accept_object),
         false <- target.local do
      Delivery.deliver(actor, target.inbox, accept_object.data)
    end
  end

  defp accepted_follower(%Object{} = accept_object) do
    case accept_object.data["object"] do
      %{"actor" => actor} when is_binary(actor) ->
        Users.get_by_ap_id(actor)

      object_id when is_binary(object_id) ->
        case Objects.get_by_ap_id(object_id) do
          %Object{actor: actor} when is_binary(actor) -> Users.get_by_ap_id(actor)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp accepted_target(%Object{} = accept_object) do
    accepted_follower(accept_object) || accepted_offer_actor(accept_object)
  end

  defp accepted_offer_actor(%Object{} = accept_object) do
    case accept_object.data["object"] do
      %{} = offer ->
        if TypeNormalizer.primary_type(offer) == "Offer" do
          offer
          |> Map.get("actor")
          |> extract_id()
          |> Users.get_by_ap_id()
        else
          nil
        end

      offer_ap_id when is_binary(offer_ap_id) ->
        case Objects.get_by_ap_id(offer_ap_id) do
          %Object{type: "Offer", actor: actor} when is_binary(actor) ->
            Users.get_by_ap_id(actor)

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp to_object_attrs(activity, opts) do
    %{
      ap_id: activity["id"],
      type: activity["type"],
      actor: activity["actor"],
      object: extract_object_id(activity["object"]),
      data: activity,
      published: Helpers.parse_datetime(activity["published"]),
      local: Keyword.get(opts, :local, true)
    }
    |> Helpers.attach_type_metadata(opts)
  end

  defp apply_accept(activity, %__MODULE__{} = accept) do
    object_value = accept.embedded_object || accept.object

    activity
    |> Map.put("id", accept.id)
    |> Map.put("type", accept.type)
    |> Map.put("actor", accept.actor)
    |> Map.put("object", object_value)
    |> Helpers.maybe_put("to", accept.to)
    |> Helpers.maybe_put("cc", accept.cc)
    |> Helpers.maybe_put("published", accept.published)
  end

  defp maybe_embed_object(%{"object" => %{} = object} = activity) do
    Map.put(activity, "embedded_object", object)
  end

  defp maybe_embed_object(activity), do: activity

  defp extract_object_id(%{"id" => id}) when is_binary(id), do: id
  defp extract_object_id(id) when is_binary(id), do: id
  defp extract_object_id(_), do: nil
end
