defmodule Egregoros.Activities.Offer do
  use Ecto.Schema

  import Ecto.Changeset

  alias Egregoros.Activities.Helpers
  alias Egregoros.ActivityPub.ObjectValidators.Types.DateTime, as: APDateTime
  alias Egregoros.ActivityPub.ObjectValidators.Types.ObjectID
  alias Egregoros.ActivityPub.ObjectValidators.Types.Recipients
  alias Egregoros.ActivityPub.TypeNormalizer
  alias Egregoros.Domain
  alias Egregoros.InboxTargeting
  alias Egregoros.Notifications
  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Recipients, as: RecipientHelpers
  alias Egregoros.Relationships
  alias Egregoros.User
  alias Egregoros.Users
  alias EgregorosWeb.Endpoint

  def type, do: "Offer"

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

  def build(%User{ap_id: actor}, %Object{} = object) do
    build(actor, object)
  end

  def build(actor, %Object{ap_id: object_id})
      when is_binary(actor) and is_binary(object_id) do
    build(actor, object_id)
  end

  def build(%User{ap_id: actor}, object_id) when is_binary(object_id) do
    build(actor, object_id)
  end

  def build(actor, object_id) when is_binary(actor) and is_binary(object_id) do
    %{
      "id" => Endpoint.url() <> "/activities/offer/" <> Ecto.UUID.generate(),
      "type" => type(),
      "actor" => actor,
      "object" => object_id,
      "published" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  def cast_and_validate(activity) when is_map(activity) do
    activity = maybe_embed_object(activity)

    changeset =
      %__MODULE__{}
      |> cast(activity, __schema__(:fields))
      |> validate_required([:id, :type, :actor, :object])
      |> validate_inclusion(:type, [type()])
      |> validate_object()
      |> validate_offer_credential_domain()

    case apply_action(changeset, :insert) do
      {:ok, %__MODULE__{} = offer} -> {:ok, apply_offer(activity, offer)}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

  def ingest(%{"object" => %{} = embedded_object} = activity, opts) do
    with :ok <- validate_inbox_target(activity, opts),
         # Offers can include objects that aren't addressed directly to the inbox user,
         # so we bypass inbox targeting for the embedded object itself.
         {:ok, object} <-
           Pipeline.ingest(embedded_object, Keyword.delete(opts, :inbox_user_ap_id)) do
      activity
      |> to_object_attrs(object.ap_id, opts)
      |> Objects.upsert_object()
    end
  end

  def ingest(activity, opts) do
    with :ok <- validate_inbox_target(activity, opts) do
      activity
      |> to_object_attrs(extract_object_id(activity["object"]), opts)
      |> Objects.upsert_object()
    end
  end

  def side_effects(%Object{} = offer_object, opts) do
    offer_object
    |> recipient_ap_ids(opts)
    |> Enum.each(fn recipient_ap_id ->
      case Users.get_by_ap_id(recipient_ap_id) do
        %User{local: true} = user ->
          Notifications.broadcast(user.ap_id, offer_object)
          :ok

        _ ->
          :ok
      end

      _ = upsert_offer_relationship(recipient_ap_id, offer_object.ap_id)
    end)

    :ok
  end

  def side_effects(_object, _opts), do: :ok

  defp upsert_offer_relationship(recipient_ap_id, offer_ap_id)
       when is_binary(recipient_ap_id) and is_binary(offer_ap_id) do
    recipient_ap_id = String.trim(recipient_ap_id)
    offer_ap_id = String.trim(offer_ap_id)

    if recipient_ap_id == "" or offer_ap_id == "" do
      :ok
    else
      Relationships.upsert_relationship(%{
        type: "OfferPending",
        actor: recipient_ap_id,
        object: offer_ap_id,
        activity_ap_id: offer_ap_id
      })

      :ok
    end
  end

  defp upsert_offer_relationship(_recipient_ap_id, _offer_ap_id), do: :ok

  def recipient_ap_ids(%Object{} = offer_object, opts \\ []) when is_list(opts) do
    activity_recipients = offer_recipients_from_activity(offer_object)
    credential_recipients = credential_recipients(offer_object)

    activity_recipients
    |> Kernel.++(credential_recipients)
    |> Enum.uniq()
    |> add_inbox_recipient(opts)
  end

  defp validate_inbox_target(%{} = activity, opts) when is_list(opts) do
    if Keyword.get(opts, :skip_inbox_target, false) do
      :ok
    else
      InboxTargeting.validate_addressed_or_followed_or_addressed_to_object(
        opts,
        activity,
        Map.get(activity, "actor"),
        Map.get(activity, "object")
      )
    end
  end

  defp validate_inbox_target(_activity, _opts), do: :ok

  defp to_object_attrs(activity, object_id, opts) do
    %{
      ap_id: activity["id"],
      type: activity["type"],
      actor: activity["actor"],
      object: object_id,
      data: activity,
      published: Helpers.parse_datetime(activity["published"]),
      local: Keyword.get(opts, :local, true)
    }
    |> Helpers.attach_type_metadata(opts)
  end

  defp apply_offer(activity, %__MODULE__{} = offer) do
    object_value = offer.embedded_object || offer.object

    activity
    |> Map.put("id", offer.id)
    |> Map.put("type", offer.type)
    |> Map.put("actor", offer.actor)
    |> Map.put("object", object_value)
    |> Helpers.maybe_put("to", offer.to)
    |> Helpers.maybe_put("cc", offer.cc)
    |> Helpers.maybe_put("published", offer.published)
  end

  defp offer_recipients_from_activity(%Object{data: %{} = data}) do
    RecipientHelpers.recipient_actor_ids(data)
  end

  defp offer_recipients_from_activity(_offer_object), do: []

  defp add_inbox_recipient(recipients, opts) when is_list(recipients) and is_list(opts) do
    case Keyword.get(opts, :inbox_user_ap_id) do
      inbox_user_ap_id when is_binary(inbox_user_ap_id) ->
        inbox_user_ap_id = String.trim(inbox_user_ap_id)

        if inbox_user_ap_id == "" do
          recipients
        else
          Enum.uniq([inbox_user_ap_id | recipients])
        end

      _ ->
        recipients
    end
  end

  defp credential_recipients(%Object{} = offer_object) do
    offer_object
    |> credential_data_from_offer()
    |> credential_subject_ids()
  end

  defp credential_data_from_offer(%Object{data: %{"object" => %{} = credential}}),
    do: credential

  defp credential_data_from_offer(%Object{object: credential_ap_id})
       when is_binary(credential_ap_id) do
    case Objects.get_by_ap_id(credential_ap_id) do
      %Object{data: %{} = credential} -> credential
      _ -> nil
    end
  end

  defp credential_data_from_offer(_offer_object), do: nil

  defp credential_subject_ids(%{} = credential) do
    credential
    |> Map.get("credentialSubject")
    |> List.wrap()
    |> Enum.map(&extract_recipient_id/1)
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp credential_subject_ids(_credential), do: []

  defp extract_recipient_id(%{"id" => id}) when is_binary(id), do: id
  defp extract_recipient_id(%{id: id}) when is_binary(id), do: id
  defp extract_recipient_id(id) when is_binary(id), do: id
  defp extract_recipient_id(_recipient), do: nil

  defp validate_object(changeset) do
    embedded_object = get_field(changeset, :embedded_object)

    if is_map(embedded_object) do
      object_id = get_in(embedded_object, ["id"]) || get_in(embedded_object, [:id])
      # Accept multi-type objects by validating against the primary type only.
      object_type = TypeNormalizer.primary_type(embedded_object)

      if is_binary(object_id) and object_id != "" and is_binary(object_type) and
           object_type != "" do
        changeset
      else
        add_error(changeset, :object, "must be an object with id and type")
      end
    else
      changeset
    end
  end

  defp validate_offer_credential_domain(changeset) do
    embedded_object = get_field(changeset, :embedded_object)

    if is_map(embedded_object) and
         TypeNormalizer.primary_type(embedded_object) == "VerifiableCredential" do
      offer_id = get_field(changeset, :id)
      credential_id = get_in(embedded_object, ["id"]) || get_in(embedded_object, [:id])

      if same_domain?(offer_id, credential_id) do
        changeset
      else
        add_error(changeset, :object, "offer and credential must share a domain")
      end
    else
      changeset
    end
  end

  defp same_domain?(offer_id, credential_id)
       when is_binary(offer_id) and is_binary(credential_id) do
    offer_domain = offer_id |> URI.parse() |> Domain.from_uri()
    credential_domain = credential_id |> URI.parse() |> Domain.from_uri()

    is_binary(offer_domain) and is_binary(credential_domain) and offer_domain == credential_domain
  end

  defp same_domain?(_offer_id, _credential_id), do: false

  defp extract_object_id(%{"id" => id}) when is_binary(id), do: id
  defp extract_object_id(id) when is_binary(id), do: id
  defp extract_object_id(_), do: nil

  defp maybe_embed_object(%{"object" => %{} = object} = activity) do
    Map.put(activity, "embedded_object", object)
  end

  defp maybe_embed_object(activity), do: activity
end
