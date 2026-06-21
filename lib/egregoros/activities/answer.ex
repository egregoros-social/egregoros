defmodule Egregoros.Activities.Answer do
  @moduledoc """
  Activity handler for ActivityPub Answer objects (poll votes).

  Answers have:
  - `name`: The text of the chosen poll option
  - `inReplyTo`: The ap_id of the Question being answered
  - `actor`/`attributedTo`: Who voted

  Side effects update the Question's vote count when an Answer is ingested.

  ## Inbox Targeting

  Answers are accepted if we have the Question in our database and the voter
  is permitted to vote on it (i.e., the voter is in the Question's audience).
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Egregoros.Activities.Helpers
  alias Egregoros.Activities.Validations
  alias Egregoros.ActivityPub.ObjectValidators.Types.ObjectID
  alias Egregoros.ActivityPub.ObjectValidators.Types.Recipients
  alias Egregoros.ActivityPub.ObjectValidators.Types.DateTime, as: APDateTime
  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Relationships
  alias Egregoros.Timeline

  @as_public "https://www.w3.org/ns/activitystreams#Public"

  def type, do: "Answer"

  @primary_key false
  embedded_schema do
    field :id, ObjectID
    field :type, :string
    field :actor, ObjectID
    field :attributedTo, ObjectID
    field :name, :string
    field :inReplyTo, ObjectID
    field :context, :string
    field :to, Recipients
    field :cc, Recipients
    field :published, APDateTime
  end

  def cast_and_validate(answer) when is_map(answer) do
    cast_and_validate(answer, [])
  end

  def cast_and_validate(answer, opts) when is_map(answer) and is_list(opts) do
    answer =
      answer
      |> normalize_actor()
      |> normalize_in_reply_to()

    changeset =
      %__MODULE__{}
      |> cast(answer, __schema__(:fields))
      |> validate_required([:id, :type, :actor, :attributedTo, :name, :inReplyTo])
      |> validate_inclusion(:type, [type()])
      |> Validations.validate_any_presence([:to, :cc])
      |> Validations.validate_fields_match([:actor, :attributedTo])
      |> Validations.validate_host_match([:id, :actor, :attributedTo])

    with {:ok, %__MODULE__{} = validated} <- apply_action(changeset, :insert),
         :ok <- validate_question_exists_and_permits_voter(answer, opts) do
      {:ok, apply_answer(answer, validated)}
    end
  end

  def to_object_attrs(answer, opts) do
    %{
      ap_id: answer["id"],
      type: answer["type"],
      actor: answer["actor"],
      object: answer["inReplyTo"],
      data: answer,
      published: Helpers.parse_datetime(answer["published"]),
      local: Keyword.get(opts, :local, true)
    }
    |> Helpers.attach_type_metadata(opts)
  end

  def ingest(answer, opts) do
    answer
    |> to_object_attrs(opts)
    |> Objects.upsert_object()
  end

  def side_effects(object, _opts) do
    with %{data: %{"inReplyTo" => question_ap_id, "name" => name, "actor" => actor}}
         when is_binary(question_ap_id) and is_binary(name) and is_binary(actor) <- object do
      case Objects.increase_vote_count(question_ap_id, name, actor) do
        {:ok, updated_poll} ->
          Timeline.broadcast_post_updated(updated_poll)

        _ ->
          :ok
      end
    end

    :ok
  end

  # Normalization

  defp apply_answer(answer, %__MODULE__{} = validated) do
    answer
    |> Map.put("id", validated.id)
    |> Map.put("type", validated.type)
    |> Map.put("actor", validated.actor)
    |> Helpers.maybe_put("attributedTo", validated.attributedTo)
    |> Map.put("name", validated.name)
    |> Map.put("inReplyTo", validated.inReplyTo)
    |> Helpers.maybe_put("context", validated.context)
    |> Helpers.maybe_put("to", validated.to)
    |> Helpers.maybe_put("cc", validated.cc)
    |> Helpers.maybe_put("published", validated.published)
  end

  defp normalize_actor(%{"actor" => _} = answer), do: answer

  defp normalize_actor(%{"attributedTo" => actor} = answer) do
    Map.put(answer, "actor", actor)
  end

  defp normalize_actor(answer), do: answer

  defp normalize_in_reply_to(%{"inReplyTo" => reply_to} = answer) when is_binary(reply_to) do
    answer
  end

  defp normalize_in_reply_to(%{"inReplyTo" => %{"id" => reply_to}} = answer)
       when is_binary(reply_to) do
    Map.put(answer, "inReplyTo", reply_to)
  end

  defp normalize_in_reply_to(answer), do: answer

  # Inbox targeting validation
  # Accept the Answer if we have the Question and the voter is permitted to vote on it

  defp validate_question_exists_and_permits_voter(answer, opts) do
    # Local answers skip this validation
    if Keyword.get(opts, :local, true) do
      :ok
    else
      question_ap_id = Map.get(answer, "inReplyTo")
      voter_ap_id = Map.get(answer, "actor")

      case Objects.get_by_ap_id(question_ap_id) do
        %Object{type: "Question", data: data} when is_map(data) ->
          if voter_permitted?(data, voter_ap_id) do
            :ok
          else
            {:error, :voter_not_permitted}
          end

        _ ->
          # We don't have the Question, reject the Answer
          {:error, :question_not_found}
      end
    end
  end

  defp voter_permitted?(question_data, voter_ap_id) when is_map(question_data) do
    # Check if the poll is public or if the voter is in the audience
    to = Map.get(question_data, "to", []) |> List.wrap()
    cc = Map.get(question_data, "cc", []) |> List.wrap()
    audience = to ++ cc

    @as_public in audience or voter_ap_id in audience or
      voter_in_followers_collection?(audience, voter_ap_id)
  end

  defp voter_permitted?(_question_data, _voter_ap_id), do: false

  defp voter_in_followers_collection?(audience, voter_ap_id)
       when is_list(audience) and is_binary(voter_ap_id) do
    follower_actor_ids =
      audience
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.filter(&String.ends_with?(&1, "/followers"))
      |> Enum.map(&String.replace_suffix(&1, "/followers", ""))
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    follower_actor_ids != [] and
      Relationships.list_follows_by_actor_for_objects(voter_ap_id, follower_actor_ids) != []
  end

  defp voter_in_followers_collection?(_audience, _voter_ap_id), do: false
end
