defmodule Egregoros.ModerationConformanceTest do
  @moduledoc """
  Drives every covered surface from `Egregoros.ModerationCases`.

  Each surface gets the same cases, so adding a moderation case means editing the
  table once rather than rediscovering every surface. A case marked as a known
  gap for a surface asserts the current (wrong) behavior and says so in the
  failure message, so fixing the code fails this test until the marker is
  removed.
  """
  use Egregoros.DataCase, async: true

  alias Egregoros.ModerationCases
  alias Egregoros.Notifications
  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Publish
  alias Egregoros.Relationships
  alias Egregoros.Users

  setup do
    {:ok, viewer} = Users.create_local_user("viewer")
    {:ok, author} = Users.create_local_user("author")
    {:ok, third_party} = Users.create_local_user("thirdparty")

    # The viewer follows the author throughout, so followers-only cases isolate
    # moderation state rather than follow state.
    :ok = put_relationship("Follow", viewer, author)

    %{viewer: viewer, author: author, third_party: third_party}
  end

  # ---------------------------------------------------------------- fixtures

  defp apply_relationship(:none, _viewer, _author), do: :ok

  defp apply_relationship(:viewer_blocks_author, viewer, author),
    do: block(viewer, author)

  defp apply_relationship(:author_blocks_viewer, viewer, author),
    do: block(author, viewer)

  defp apply_relationship(:viewer_mutes_author, viewer, author),
    do: put_relationship("Mute", viewer, author)

  # Both real block paths (AccountsController.block/2 and ProfileLive) sever the
  # follow in both directions, so a fixture that left it in place would build
  # state the application cannot reach.
  defp block(blocker, blocked) do
    :ok = put_relationship("Block", blocker, blocked)
    Relationships.delete_by_type_actor_object("Follow", blocker.ap_id, blocked.ap_id)
    Relationships.delete_by_type_actor_object("Follow", blocked.ap_id, blocker.ap_id)
    :ok
  end

  defp relationship_present?(:none, _viewer, _author), do: true

  defp relationship_present?(:viewer_blocks_author, viewer, author),
    do: Relationships.get_by_type_actor_object("Block", viewer.ap_id, author.ap_id) != nil

  defp relationship_present?(:author_blocks_viewer, viewer, author),
    do: Relationships.get_by_type_actor_object("Block", author.ap_id, viewer.ap_id) != nil

  defp relationship_present?(:viewer_mutes_author, viewer, author),
    do: Relationships.get_by_type_actor_object("Mute", viewer.ap_id, author.ap_id) != nil

  defp put_relationship(type, actor, object) do
    {:ok, _} =
      Relationships.upsert_relationship(%{
        type: type,
        actor: actor.ap_id,
        object: object.ap_id,
        activity_ap_id: nil
      })

    :ok
  end

  defp create_object!(test_case, %{viewer: viewer, author: author, third_party: third_party}) do
    visibility =
      case test_case.audience do
        :public -> "public"
        :unlisted -> "unlisted"
        :followers_only -> "private"
        :direct -> "direct"
      end

    # Whether the viewer is mentioned is a case dimension, not a fixture
    # convenience: a mention makes them an explicit recipient, which short-cuts
    # the followers-only and audience logic and is also what makes a post
    # notification-worthy.
    content =
      cond do
        test_case.mentions_viewer -> "@#{viewer.nickname} hello"
        # A direct message has to be addressed to somebody.
        test_case.audience == :direct -> "@#{third_party.nickname} hello"
        true -> "a post with no mention"
      end

    {:ok, create} = Publish.post_note(author, content, visibility: visibility)

    Objects.get_by_ap_id(create.object)
  end

  # ------------------------------------------------------------------ probes

  defp observe(:object_visibility, object, %{viewer: viewer}) do
    if Objects.visible_to?(object, viewer), do: :visible, else: :hidden
  end

  defp observe(:public_timeline, object, _actors) do
    presence(Objects.list_public_statuses(limit: 50), object)
  end

  defp observe(:home_timeline, object, %{viewer: viewer}) do
    presence(Objects.list_home_statuses(viewer.ap_id, limit: 50), object)
  end

  # Notifications are returned as the activity/object rows themselves, so the
  # same presence check works here.
  defp observe(:notifications, object, %{viewer: viewer}) do
    presence(Notifications.list_for_user(viewer, limit: 50), object)
  end

  # All four surfaces return %Object{} rows.
  defp presence(entries, %Object{id: id}) do
    if Enum.any?(entries, &match?(%Object{id: ^id}, &1)), do: :visible, else: :hidden
  end

  # ------------------------------------------------------------------- table

  for surface <- ModerationCases.surfaces() do
    describe "#{surface}" do
      for test_case <- ModerationCases.cases_for(surface) do
        @surface surface
        @test_case test_case

        test "#{test_case.id}: #{test_case.description}", actors do
          :ok = apply_relationship(@test_case.relationship, actors.viewer, actors.author)

          # Without this, a gap assertion ("still visible despite the block") is
          # indistinguishable from the no-moderation baseline, so a fixture that
          # silently stopped writing the row would still pass.
          assert relationship_present?(@test_case.relationship, actors.viewer, actors.author),
                 "fixture did not create the #{@test_case.relationship} relationship"

          object = create_object!(@test_case, actors)

          actual = observe(@surface, object, actors)
          {want, status} = ModerationCases.outcome_for(@test_case, @surface)

          case status do
            :conforms ->
              assert actual == want,
                     """
                     #{@surface} disagrees with the moderation table.

                       case:     #{@test_case.id} (#{@test_case.description})
                       expected: #{want}
                       actual:   #{actual}

                     Either the surface has a bug, or the table is wrong. Fix one \
                     of them — do not special-case this test.
                     """

            :known_gap ->
              assert actual == want,
                     """
                     #{@surface} no longer matches its recorded gap for \
                     #{@test_case.id}.

                       recorded (current, wrong): #{want}
                       observed:                  #{actual}
                       intended:                  #{@test_case.expected}

                     If you fixed this, remove :#{@surface} from the :gaps list \
                     for #{@test_case.id} in Egregoros.ModerationCases.
                     """
          end
        end
      end
    end
  end
end
