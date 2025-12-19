defmodule PleromaReduxWeb.MastodonAPI.RelationshipRenderer do
  alias PleromaRedux.Relationships
  alias PleromaRedux.User

  def render_relationship(%User{} = actor, %User{} = target) do
    following? =
      Relationships.get_by_type_actor_object("Follow", actor.ap_id, target.ap_id) != nil

    followed_by? =
      Relationships.get_by_type_actor_object("Follow", target.ap_id, actor.ap_id) != nil

    %{
      "id" => Integer.to_string(target.id),
      "following" => following?,
      "showing_reblogs" => true,
      "notifying" => false,
      "languages" => [],
      "followed_by" => followed_by?,
      "blocking" => false,
      "blocked_by" => false,
      "muting" => false,
      "muting_notifications" => false,
      "requested" => false,
      "domain_blocking" => false,
      "endorsed" => false,
      "note" => ""
    }
  end
end
