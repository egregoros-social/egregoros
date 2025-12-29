defmodule EgregorosWeb.MastodonAPI.RelationshipRenderer do
  alias Egregoros.Relationships
  alias Egregoros.User

  def render_relationship(%User{} = actor, %User{} = target) do
    following? =
      Relationships.get_by_type_actor_object("Follow", actor.ap_id, target.ap_id) != nil

    followed_by? =
      Relationships.get_by_type_actor_object("Follow", target.ap_id, actor.ap_id) != nil

    requested? =
      not following? and
        Relationships.get_by_type_actor_object("FollowRequest", actor.ap_id, target.ap_id) != nil

    blocking? =
      Relationships.get_by_type_actor_object("Block", actor.ap_id, target.ap_id) != nil

    blocked_by? =
      Relationships.get_by_type_actor_object("Block", target.ap_id, actor.ap_id) != nil

    muting? =
      Relationships.get_by_type_actor_object("Mute", actor.ap_id, target.ap_id) != nil

    %{
      "id" => Integer.to_string(target.id),
      "following" => following?,
      "showing_reblogs" => true,
      "notifying" => false,
      "languages" => [],
      "followed_by" => followed_by?,
      "blocking" => blocking?,
      "blocked_by" => blocked_by?,
      "muting" => muting?,
      "muting_notifications" => false,
      "requested" => requested?,
      "domain_blocking" => false,
      "endorsed" => false,
      "note" => ""
    }
  end
end
