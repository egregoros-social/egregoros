defmodule Egregoros.Activities.Move do
  use Ecto.Schema

  import Ecto.Changeset

  alias Egregoros.Activities.Follow
  alias Egregoros.Activities.Helpers
  alias Egregoros.Activities.Undo
  alias Egregoros.ActivityPub.ObjectValidators.Types.DateTime, as: APDateTime
  alias Egregoros.ActivityPub.ObjectValidators.Types.ObjectID
  alias Egregoros.ActivityPub.ObjectValidators.Types.Recipients
  alias Egregoros.Federation.Actor
  alias Egregoros.InboxTargeting
  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Relationship
  alias Egregoros.Relationships
  alias Egregoros.Repo
  alias Egregoros.User
  alias Egregoros.Users
  alias Egregoros.Pipeline

  def type, do: "Move"

  @primary_key false
  embedded_schema do
    field :id, ObjectID
    field :type, :string
    field :actor, ObjectID
    field :object, ObjectID
    field :target, ObjectID
    field :to, Recipients
    field :cc, Recipients
    field :published, APDateTime
  end

  def cast_and_validate(activity) when is_map(activity) do
    changeset =
      %__MODULE__{}
      |> cast(activity, __schema__(:fields))
      |> validate_required([:id, :type, :actor, :object, :target])
      |> validate_inclusion(:type, [type()])
      |> validate_object_matches_actor()

    case apply_action(changeset, :insert) do
      {:ok, %__MODULE__{} = move} -> {:ok, apply_move(activity, move)}
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

  def side_effects(%Object{} = move_object, opts) do
    if Keyword.get(opts, :local, true) do
      :ok
    else
      _ = maybe_apply_move(move_object)
    end

    :ok
  end

  defp maybe_apply_move(%Object{actor: actor_ap_id, data: %{} = data})
       when is_binary(actor_ap_id) do
    target_ap_id =
      data
      |> Map.get("target")
      |> normalize_ap_id()

    with target_ap_id when is_binary(target_ap_id) <- target_ap_id,
         true <- target_ap_id != actor_ap_id,
         %User{} = actor <- get_or_fetch_user(actor_ap_id),
         false <- actor.local,
         %User{} = target <- get_or_fetch_user(target_ap_id),
         true <- move_confirmed_by_target?(target, actor_ap_id) do
      _ = set_moved_to(actor, target.ap_id)
      _ = migrate_local_followers(actor.ap_id, target)
      :ok
    else
      _ -> :ok
    end
  end

  defp maybe_apply_move(_move_object), do: :ok

  defp migrate_local_followers(actor_ap_id, %User{} = target) when is_binary(actor_ap_id) do
    actor_ap_id
    |> Relationships.list_follows_to()
    |> Enum.each(fn
      %Relationship{actor: follower_ap_id} = follow_rel when is_binary(follower_ap_id) ->
        with %User{} = follower <- Users.get_by_ap_id(follower_ap_id),
             true <- follower.local do
          _ = migrate_local_follower(follower, follow_rel, actor_ap_id, target)
          :ok
        else
          _ -> :ok
        end

      _ ->
        :ok
    end)

    :ok
  end

  defp migrate_local_followers(_actor_ap_id, _target), do: :ok

  defp migrate_local_follower(%User{} = follower, %Relationship{} = follow_rel, actor_ap_id, target) do
    _ = maybe_unfollow_old(follower, follow_rel, actor_ap_id)
    _ = maybe_follow_target(follower, target)
    :ok
  end

  defp maybe_unfollow_old(%User{} = follower, %Relationship{} = rel, actor_ap_id)
       when is_binary(actor_ap_id) do
    activity_ap_id = rel.activity_ap_id |> normalize_ap_id()
    follower_ap_id = follower.ap_id

    follow_object =
      case activity_ap_id do
        ap_id when is_binary(ap_id) -> Objects.get_by_ap_id(ap_id)
        _ -> nil
      end

    case follow_object do
      %Object{type: "Follow", actor: ^follower_ap_id, object: ^actor_ap_id} ->
        undo = Undo.build(follower, follow_object)
        _ = Pipeline.ingest(undo, local: true)
        :ok

      _ ->
        _ = Relationships.delete_by_type_actor_object("Follow", follower.ap_id, actor_ap_id)
        :ok
    end
  end

  defp maybe_unfollow_old(_follower, _rel, _actor_ap_id), do: :ok

  defp maybe_follow_target(%User{} = follower, %User{} = target) do
    existing =
      Relationships.get_by_type_actor_object("Follow", follower.ap_id, target.ap_id) ||
        Relationships.get_by_type_actor_object("FollowRequest", follower.ap_id, target.ap_id)

    if existing do
      :ok
    else
      follow = Follow.build(follower, target)
      _ = Pipeline.ingest(follow, local: true)
      :ok
    end
  end

  defp move_confirmed_by_target?(%User{also_known_as: also_known_as}, actor_ap_id)
       when is_binary(actor_ap_id) do
    actor_ap_id = String.trim(actor_ap_id)

    also_known_as =
      also_known_as
      |> List.wrap()
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    actor_ap_id != "" and actor_ap_id in also_known_as
  end

  defp move_confirmed_by_target?(_target, _actor_ap_id), do: false

  defp set_moved_to(%User{} = user, target_ap_id) when is_binary(target_ap_id) do
    user
    |> User.changeset(%{moved_to_ap_id: target_ap_id})
    |> Repo.update()
  end

  defp get_or_fetch_user(ap_id) when is_binary(ap_id) do
    Users.get_by_ap_id(ap_id) ||
      case Actor.fetch_and_store(ap_id) do
        {:ok, user} -> user
        _ -> nil
      end
  end

  defp validate_inbox_target(%{} = activity, opts) when is_list(opts) do
    InboxTargeting.validate(opts, fn inbox_user_ap_id ->
      actor_ap_id = Map.get(activity, "actor")

      cond do
        InboxTargeting.addressed_to?(activity, inbox_user_ap_id) ->
          :ok

        InboxTargeting.follows?(inbox_user_ap_id, actor_ap_id) ->
          :ok

        true ->
          {:error, :not_targeted}
      end
    end)
  end

  defp validate_inbox_target(_activity, _opts), do: :ok

  defp validate_object_matches_actor(changeset) do
    actor = get_field(changeset, :actor)
    object = get_field(changeset, :object)
    target = get_field(changeset, :target)

    cond do
      is_binary(actor) and is_binary(object) and actor != object ->
        add_error(changeset, :object, "must match actor")

      is_binary(actor) and is_binary(target) and actor == target ->
        add_error(changeset, :target, "must not match actor")

      true ->
        changeset
    end
  end

  defp normalize_ap_id(nil), do: nil

  defp normalize_ap_id(ap_id) when is_binary(ap_id) do
    ap_id
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_ap_id(_ap_id), do: nil

  defp to_object_attrs(activity, opts) do
    %{
      ap_id: activity["id"],
      type: activity["type"],
      actor: activity["actor"],
      object: activity["object"],
      data: activity,
      published: Helpers.parse_datetime(activity["published"]),
      local: Keyword.get(opts, :local, true)
    }
  end

  defp apply_move(activity, %__MODULE__{} = move) do
    activity
    |> Map.put("id", move.id)
    |> Map.put("type", move.type)
    |> Map.put("actor", move.actor)
    |> Map.put("object", move.object)
    |> Map.put("target", move.target)
    |> Helpers.maybe_put("to", move.to)
    |> Helpers.maybe_put("cc", move.cc)
    |> Helpers.maybe_put("published", move.published)
  end
end
