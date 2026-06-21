defmodule Egregoros.Activities.VerifiableCredential do
  use Ecto.Schema

  import Ecto.Changeset

  alias Egregoros.Activities.Helpers
  alias Egregoros.ActivityPub.ObjectValidators.Types.DateTime, as: APDateTime
  alias Egregoros.ActivityPub.ObjectValidators.Types.ObjectID
  alias Egregoros.ActivityPub.ObjectValidators.Types.Recipients
  alias Egregoros.BadgeDefinition
  alias Egregoros.Federation.InstanceActor
  alias Egregoros.InboxTargeting
  alias Egregoros.Objects
  alias Egregoros.SafeURL
  alias Egregoros.User
  alias Egregoros.Users
  alias Egregoros.VerifiableCredentials.DidWeb
  alias EgregorosWeb.Endpoint
  alias EgregorosWeb.URL

  def type, do: "VerifiableCredential"

  @primary_key false
  embedded_schema do
    field :id, ObjectID
    field :type, :string
    field :issuer, ObjectID
    field :to, Recipients
    field :cc, Recipients
    field :validFrom, APDateTime
    field :validUntil, APDateTime
  end

  def cast_and_validate(object) when is_map(object) do
    cast_and_validate(object, [])
  end

  def cast_and_validate(object, opts) when is_map(object) and is_list(opts) do
    changeset =
      %__MODULE__{}
      |> cast(object, __schema__(:fields))
      |> validate_required([:id, :type, :issuer])
      |> validate_inclusion(:type, [type()])
      |> validate_issuer()
      |> validate_recipient(object, opts)

    # TODO: Verify the embedded proof; we skip it for now because we do not yet support
    # elliptic curve instance actor keys.
    case apply_action(changeset, :insert) do
      {:ok, %__MODULE__{} = credential} -> {:ok, apply_credential(object, credential)}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

  def ingest(object, opts) do
    with :ok <- validate_inbox_target(object, opts) do
      object
      |> to_object_attrs(opts)
      |> Objects.upsert_object()
    end
  end

  def side_effects(_object, _opts), do: :ok

  defp validate_inbox_target(%{} = object, opts) when is_list(opts) do
    if Keyword.get(opts, :skip_inbox_target, false) do
      :ok
    else
      InboxTargeting.validate_addressed_or_followed(
        opts,
        object,
        issuer_ap_id(object)
      )
    end
  end

  defp validate_inbox_target(_object, _opts), do: :ok

  defp to_object_attrs(object, opts) do
    actor_id = actor_ap_id(object, opts)

    %{
      ap_id: object["id"],
      type: object["type"],
      actor: actor_id,
      object: nil,
      data: object,
      published: Helpers.parse_datetime(object["validFrom"]),
      local: Keyword.get(opts, :local, true)
    }
    # Preserve multi-type credentials by restoring the canonical type array
    # while still storing a single primary type in the database column.
    |> Helpers.attach_type_metadata(opts)
  end

  defp apply_credential(object, %__MODULE__{} = credential) do
    object
    |> Map.put("id", credential.id)
    |> Map.put("type", credential.type)
    |> Map.put("issuer", credential.issuer)
    |> Helpers.maybe_put("to", credential.to)
    |> Helpers.maybe_put("cc", credential.cc)
    |> Helpers.maybe_put("validFrom", credential.validFrom)
    |> Helpers.maybe_put("validUntil", credential.validUntil)
  end

  defp issuer_ap_id(%{"issuer" => %{"id" => id}}) when is_binary(id), do: id
  defp issuer_ap_id(%{"issuer" => id}) when is_binary(id), do: id
  defp issuer_ap_id(_object), do: nil

  defp actor_ap_id(object, opts) when is_map(object) and is_list(opts) do
    issuer_id = issuer_ap_id(object)

    if Keyword.get(opts, :local, true) and DidWeb.instance_did?(issuer_id) do
      InstanceActor.ap_id()
    else
      issuer_id
    end
  end

  defp actor_ap_id(_object, _opts), do: nil

  defp recipient_ap_id(%{"credentialSubject" => subject}) do
    subject
    |> List.wrap()
    |> Enum.find_value(fn
      %{"id" => id} when is_binary(id) -> id
      %{id: id} when is_binary(id) -> id
      id when is_binary(id) -> id
      _ -> nil
    end)
  end

  defp recipient_ap_id(_object), do: nil

  defp validate_issuer(changeset) do
    issuer = get_field(changeset, :issuer)
    issuer = if is_binary(issuer), do: String.trim(issuer), else: issuer
    user = Users.get_by_ap_id(issuer)

    cond do
      not is_binary(issuer) or issuer == "" ->
        add_error(changeset, :issuer, "must be a valid actor id")

      DidWeb.did_web?(issuer) ->
        changeset

      match?(%User{}, user) ->
        changeset

      SafeURL.validate_http_url_federation(issuer) == :ok ->
        changeset

      true ->
        add_error(changeset, :issuer, "must be a valid actor id")
    end
  end

  defp validate_recipient(changeset, object, opts) do
    recipient = recipient_ap_id(object)
    recipient = if is_binary(recipient), do: String.trim(recipient), else: recipient
    user = Users.get_by_ap_id(recipient)
    allow_remote? = Keyword.get(opts, :allow_remote_recipient, false)

    cond do
      not is_binary(recipient) or recipient == "" ->
        add_error(changeset, :credentialSubject, "must include a recipient id")

      match?(%User{local: true}, user) ->
        changeset

      allow_remote? and SafeURL.validate_http_url_federation(recipient) == :ok ->
        changeset

      match?(%User{}, user) ->
        add_error(changeset, :credentialSubject, "recipient must be local")

      SafeURL.validate_http_url_federation(recipient) == :ok ->
        add_error(changeset, :credentialSubject, "recipient must be local")

      true ->
        add_error(changeset, :credentialSubject, "recipient must be a valid actor id")
    end
  end

  def build_for_badge(badge, issuer_ap_id, recipient_ap_id, opts \\ [])

  def build_for_badge(%BadgeDefinition{} = badge, issuer_ap_id, recipient_ap_id, opts)
      when is_binary(issuer_ap_id) and is_binary(recipient_ap_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    valid_from = Keyword.get(opts, :valid_from, now)
    valid_until = Keyword.get(opts, :valid_until)

    credential = %{
      "@context" => [
        "https://www.w3.org/ns/credentials/v2",
        "https://purl.imsglobal.org/spec/ob/v3p0/context-3.0.3.json",
        audience_context()
      ],
      "id" => Endpoint.url() <> "/objects/" <> Ecto.UUID.generate(),
      "type" => ["VerifiableCredential", "OpenBadgeCredential"],
      "issuer" => issuer_ap_id,
      "to" => [recipient_ap_id],
      "validFrom" => datetime_to_iso8601(valid_from),
      "credentialSubject" => %{
        "id" => recipient_ap_id,
        "type" => "AchievementSubject",
        "achievement" => achievement_payload(badge)
      }
    }

    credential
    |> maybe_put_valid_until(valid_until)
  end

  def build_for_badge(_badge, _issuer_ap_id, _recipient_ap_id, _opts), do: %{}

  defp audience_context do
    %{
      "to" => %{"@id" => "https://www.w3.org/ns/activitystreams#to", "@type" => "@id"},
      "cc" => %{"@id" => "https://www.w3.org/ns/activitystreams#cc", "@type" => "@id"},
      "audience" => %{"@id" => "https://www.w3.org/ns/activitystreams#audience", "@type" => "@id"},
      "bto" => %{"@id" => "https://www.w3.org/ns/activitystreams#bto", "@type" => "@id"},
      "bcc" => %{"@id" => "https://www.w3.org/ns/activitystreams#bcc", "@type" => "@id"}
    }
  end

  defp achievement_payload(%BadgeDefinition{} = badge) do
    %{
      "id" => Endpoint.url() <> "/badges/" <> badge.id,
      "type" => "Achievement",
      "name" => badge.name,
      "description" => badge.description,
      "criteria" => %{"narrative" => badge.narrative}
    }
    |> maybe_put_image(badge)
  end

  defp maybe_put_image(payload, %BadgeDefinition{image_url: image_url})
       when is_binary(image_url) and image_url != "" do
    Map.put(payload, "image", %{
      "id" => URL.absolute(image_url),
      "type" => "Image"
    })
  end

  defp maybe_put_image(payload, _badge), do: payload

  defp maybe_put_valid_until(credential, %DateTime{} = valid_until) do
    Map.put(credential, "validUntil", datetime_to_iso8601(valid_until))
  end

  defp maybe_put_valid_until(credential, valid_until) when is_binary(valid_until) do
    Map.put(credential, "validUntil", valid_until)
  end

  defp maybe_put_valid_until(credential, _valid_until), do: credential

  defp datetime_to_iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
