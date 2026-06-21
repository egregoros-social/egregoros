defmodule Egregoros.Badges do
  import Ecto.Query, only: [from: 2]

  alias Egregoros.Activities.Offer
  alias Egregoros.Activities.VerifiableCredential
  alias Egregoros.BadgeDefinition
  alias Egregoros.Federation.Actor
  alias Egregoros.Federation.Delivery
  alias Egregoros.Federation.InstanceActor
  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Repo
  alias Egregoros.Relationships
  alias Egregoros.MediaStorage
  alias Egregoros.User
  alias Egregoros.Users
  alias Egregoros.VerifiableCredentials.DidWeb
  alias EgregorosWeb.URL

  def list_definitions(opts \\ []) when is_list(opts) do
    include_disabled? = Keyword.get(opts, :include_disabled?, true)

    BadgeDefinition
    |> maybe_filter_disabled(include_disabled?)
    |> then(fn query -> from(b in query, order_by: [asc: b.name]) end)
    |> Repo.all()
  end

  def list_offers(opts \\ [])

  def list_offers(opts) when is_list(opts) do
    limit = opts |> Keyword.get(:limit, 50) |> normalize_limit()

    case InstanceActor.get_actor() do
      {:ok, %User{} = issuer} ->
        Objects.list_by_type_actor("Offer", issuer.ap_id, limit: limit)
        |> Enum.flat_map(&offer_entries/1)

      _ ->
        []
    end
  end

  def list_offers(_opts), do: []

  def issue_badge(badge_type, recipient_ap_id, opts \\ [])

  def issue_badge(badge_type, recipient_ap_id, opts)
      when is_binary(badge_type) and is_binary(recipient_ap_id) and is_list(opts) do
    badge_type = String.trim(badge_type)
    recipient_ap_id = String.trim(recipient_ap_id)

    with %BadgeDefinition{} = badge <- Repo.get_by(BadgeDefinition, badge_type: badge_type),
         :ok <- ensure_enabled(badge),
         {:ok, %User{} = issuer} <- InstanceActor.get_actor(),
         {:ok, %User{} = recipient} <- resolve_recipient(recipient_ap_id),
         {:ok, %Object{} = credential} <- create_credential(badge, issuer, recipient, opts),
         {:ok, %Object{} = offer} <- create_offer(issuer, recipient, credential, opts) do
      {:ok, %{offer: offer, credential: credential, badge: badge, recipient: recipient}}
    else
      nil -> {:error, :unknown_badge}
      {:error, _} = error -> error
      _ -> {:error, :invalid_badge}
    end
  end

  def issue_badge(_badge_type, _recipient_ap_id, _opts), do: {:error, :invalid_badge}

  def badge_share_flash_message(%User{} = user, post_id) when is_binary(post_id) do
    with %Object{type: "VerifiableCredential", ap_id: ap_id} <- Objects.get(post_id) do
      case Relationships.get_by_type_actor_object("Announce", user.ap_id, ap_id) do
        %{} -> "Badge shared."
        _ -> "Badge unshared."
      end
    else
      _ -> nil
    end
  end

  def badge_share_flash_message(_user, _post_id), do: nil

  def update_definition(%BadgeDefinition{} = badge, params) when is_map(params) do
    {upload, params} = Map.pop(params, "image")
    {upload, params} = if is_nil(upload), do: Map.pop(params, :image), else: {upload, params}

    with {:ok, params} <- maybe_put_badge_image(params, upload),
         params <- normalize_image_url(params),
         changeset <- BadgeDefinition.changeset(badge, params),
         {:ok, %BadgeDefinition{} = badge} <- Repo.update(changeset) do
      {:ok, badge}
    end
  end

  def update_definition(_badge, _params), do: {:error, :invalid_badge}

  defp maybe_filter_disabled(query, true), do: query

  defp maybe_filter_disabled(query, false) do
    from(b in query, where: b.disabled == false)
  end

  defp normalize_limit(limit) when is_integer(limit), do: limit |> max(1) |> min(100)
  defp normalize_limit(_limit), do: 50

  defp ensure_enabled(%BadgeDefinition{disabled: true}), do: {:error, :disabled_badge}
  defp ensure_enabled(%BadgeDefinition{}), do: :ok

  defp maybe_put_badge_image(params, %Plug.Upload{} = upload) do
    with {:ok, %User{} = instance_actor} <- InstanceActor.get_actor(),
         {:ok, url_path} <- MediaStorage.store_media(instance_actor, upload) do
      {:ok, Map.put(params, "image_url", URL.absolute(url_path))}
    else
      {:error, _} = error -> error
      _ -> {:error, :badge_image_upload_failed}
    end
  end

  defp maybe_put_badge_image(params, _upload), do: {:ok, params}

  defp normalize_image_url(params) when is_map(params) do
    image_url =
      Map.get(params, "image_url") ||
        Map.get(params, :image_url)

    if is_binary(image_url) do
      trimmed = String.trim(image_url)

      if trimmed == "" do
        Map.put(params, "image_url", "")
      else
        Map.put(params, "image_url", URL.absolute(trimmed))
      end
    else
      params
    end
  end

  defp resolve_recipient(ap_id) when is_binary(ap_id) do
    ap_id = String.trim(ap_id)

    cond do
      ap_id == "" ->
        {:error, :invalid_recipient}

      true ->
        case Users.get_by_ap_id(ap_id) do
          %User{} = user -> {:ok, user}
          _ -> Actor.fetch_and_store(ap_id)
        end
    end
  end

  defp resolve_recipient(_ap_id), do: {:error, :invalid_recipient}

  defp create_credential(%BadgeDefinition{} = badge, %User{} = issuer, %User{} = recipient, opts) do
    issuer_id = DidWeb.instance_did() || issuer.ap_id

    credential =
      VerifiableCredential.build_for_badge(
        badge,
        issuer_id,
        recipient.ap_id,
        opts
      )

    Pipeline.ingest(credential,
      local: true,
      allow_remote_recipient: true,
      skip_inbox_target: true
    )
  end

  defp create_offer(%User{} = issuer, %User{} = recipient, %Object{} = credential, opts) do
    offer =
      Offer.build(issuer, credential)
      |> Map.put("to", [recipient.ap_id])

    with {:ok, %Object{} = offer_object} <-
           Pipeline.ingest(offer, local: true, skip_inbox_target: true),
         :ok <- maybe_deliver_offer(issuer, recipient, offer_object, credential, opts) do
      {:ok, offer_object}
    end
  end

  defp offer_entries(%Object{} = offer) do
    recipients =
      offer
      |> Offer.recipient_ap_ids()
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    credential = credential_from_offer(offer)
    {badge_name, badge_description} = badge_details(credential)
    issued_at = offer.published || offer.inserted_at

    Enum.map(recipients, fn recipient_ap_id ->
      %{
        offer: offer,
        recipient_ap_id: recipient_ap_id,
        recipient: Users.get_by_ap_id(recipient_ap_id),
        status: offer_status(recipient_ap_id, offer.ap_id),
        badge_name: badge_name,
        badge_description: badge_description,
        issued_at: issued_at
      }
    end)
  end

  defp offer_entries(_offer), do: []

  defp offer_status(recipient_ap_id, offer_ap_id)
       when is_binary(recipient_ap_id) and is_binary(offer_ap_id) do
    cond do
      Relationships.get_by_type_actor_object("OfferAccepted", recipient_ap_id, offer_ap_id) ->
        "Accepted"

      Relationships.get_by_type_actor_object("OfferRejected", recipient_ap_id, offer_ap_id) ->
        "Rejected"

      Relationships.get_by_type_actor_object("OfferPending", recipient_ap_id, offer_ap_id) ->
        "Pending"

      true ->
        "Pending"
    end
  end

  defp offer_status(_recipient_ap_id, _offer_ap_id), do: "Pending"

  defp credential_from_offer(%Object{data: %{"object" => %{} = credential}}), do: credential

  defp credential_from_offer(%Object{object: credential_ap_id})
       when is_binary(credential_ap_id) do
    case Objects.get_by_ap_id(credential_ap_id) do
      %Object{data: %{} = data} -> data
      _ -> nil
    end
  end

  defp credential_from_offer(_offer), do: nil

  defp badge_details(%{} = credential) do
    achievement =
      credential
      |> Map.get("credentialSubject")
      |> List.wrap()
      |> Enum.find(&is_map/1)
      |> case do
        %{} = subject -> Map.get(subject, "achievement") || Map.get(subject, :achievement)
        _ -> nil
      end

    {
      achievement_field(achievement, "name"),
      achievement_field(achievement, "description")
    }
  end

  defp badge_details(_credential), do: {nil, nil}

  defp achievement_field(%{} = achievement, "name") do
    Map.get(achievement, "name") || Map.get(achievement, :name)
  end

  defp achievement_field(%{} = achievement, "description") do
    Map.get(achievement, "description") || Map.get(achievement, :description)
  end

  defp achievement_field(_achievement, _key), do: nil

  defp maybe_deliver_offer(%User{}, %User{local: true}, _offer, _credential, _opts), do: :ok

  defp maybe_deliver_offer(
         %User{} = issuer,
         %User{} = recipient,
         %Object{} = offer,
         %Object{} = credential,
         _opts
       ) do
    inbox = recipient.inbox |> to_string() |> String.trim()

    if inbox == "" do
      {:error, :invalid_recipient}
    else
      payload = Map.put(offer.data, "object", credential.data)

      case Delivery.deliver(issuer, inbox, payload) do
        {:ok, _job} -> :ok
        {:error, _} = error -> error
      end
    end
  end
end
