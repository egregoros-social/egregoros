defmodule Egregoros.ModerationCases do
  @moduledoc """
  One shared truth table for visibility, block, and mute semantics.

  Every surface that decides "may this viewer see this?" should be driven from
  this list rather than from cases invented per test file, because that is how
  surfaces drift apart and privacy leaks appear.

  ## Reading a case

    * `:audience` — how the object is addressed (`:public`, `:unlisted`,
      `:followers_only`, `:direct`).
    * `:mentions_viewer` — whether the post mentions the viewer. This is explicit
      because it changes which code path decides visibility: a mention makes the
      viewer an *explicit recipient*, which short-circuits the followers-only and
      audience logic entirely. It is also what makes a post notification-worthy.
    * `:relationship` — the moderation state between viewer and author.
    * `:expected` — `:visible` or `:hidden`: the intended semantics.
    * `:expected_per_surface` — overrides `:expected` for surfaces where a
      different answer is correct rather than buggy. A mute, for instance, should
      hide content from feeds while leaving it reachable if you go looking.
    * `:gaps` — surfaces where current behavior does **not** match the intent.
    * `:only` — surfaces where the case is meaningful at all.

  ## Why `:gaps` exists

  This is a characterization table: it records what the code does today, not only
  what it ought to do. A surface listed in `:gaps` is asserted to produce the
  *wrong* answer, so the conformance test fails when someone fixes it — which is
  the prompt to delete the marker.

  Note the limit of that design: a gap assertion says "the moderation state is in
  place and the content is still visible", which is the same *outcome* the
  no-moderation baseline asserts. The conformance test therefore also asserts the
  moderation row exists, so a broken fixture fails loudly instead of quietly
  turning these into duplicates of the baseline.

  Fixing a gap is deliberately not part of maintaining this table. See
  `meta/issues/enforce-blocks-and-mutes-across-surfaces.md`.

  ## Surfaces

  Driven by this table today:

    * `:object_visibility` — `Egregoros.Objects.visible_to?/2`. Not a single
      endpoint: it is the shared visibility predicate with ~45 call sites,
      including the Mastodon status controllers, the streaming socket, and the
      timeline/status LiveViews. A gap here is correspondingly broad.
    * `:public_timeline` — `Egregoros.Objects.list_public_statuses/1`. Note it
      takes no viewer, so it cannot apply per-viewer moderation at all today.
    * `:home_timeline` — `Egregoros.Objects.list_home_statuses/2`
    * `:notifications` — `Egregoros.Notifications.list_for_user/2`. Only the
      mention predicate is exercised; Follow/Like/Announce/EmojiReact
      notifications have no axis in this table yet.

  Not yet driven by this table — see `uncovered_surfaces/0`, and
  `meta/issues/extend-moderation-table-to-remaining-surfaces.md`. Note that
  `GET /objects/:uuid` is *not* among the covered surfaces: it uses
  `publicly_visible?/1`, which takes no viewer and so has no moderation
  dimension.
  """

  @type surface :: :object_visibility | :public_timeline | :home_timeline | :notifications
  @type audience :: :public | :unlisted | :followers_only | :direct
  @type relationship ::
          :none | :viewer_blocks_author | :author_blocks_viewer | :viewer_mutes_author

  @surfaces [:object_visibility, :public_timeline, :home_timeline, :notifications]
  @uncovered [:streaming, :liveview_refresh, :delivery]

  @doc "Every surface this table currently drives."
  def surfaces, do: @surfaces

  @doc """
  Surfaces the truth-table issue listed that this table does not yet drive.

  Exposed in code, not only prose, so the shortfall is inspectable.
  """
  def uncovered_surfaces, do: @uncovered

  @doc "The truth table."
  def cases do
    [
      # ---- baselines: no moderation state ----
      %{
        id: :public_plain,
        description: "a public post, no mention, no moderation",
        audience: :public,
        mentions_viewer: false,
        relationship: :none,
        expected: :visible,
        gaps: [],
        # Without a mention there is nothing to notify about, and the viewer only
        # sees it at home because they follow the author.
        only: [:object_visibility, :public_timeline, :home_timeline]
      },
      %{
        id: :public_mentioning_viewer,
        description: "a public post mentioning the viewer",
        audience: :public,
        mentions_viewer: true,
        relationship: :none,
        expected: :visible,
        gaps: []
      },
      %{
        id: :unlisted_plain,
        description: "an unlisted post",
        audience: :unlisted,
        mentions_viewer: false,
        relationship: :none,
        # Unlisted is addressed to followers with #Public in cc: reachable and
        # visible, but deliberately absent from the public timeline. This is the
        # one case where the two visibility adapters correctly disagree.
        expected: :visible,
        expected_per_surface: %{public_timeline: :hidden},
        gaps: [],
        only: [:object_visibility, :public_timeline, :home_timeline]
      },
      %{
        id: :followers_only_plain,
        description: "a followers-only post from an author the viewer follows",
        audience: :followers_only,
        mentions_viewer: false,
        relationship: :none,
        expected: :visible,
        gaps: [],
        only: [:object_visibility, :home_timeline]
      },
      %{
        id: :direct_to_viewer,
        description: "a direct message addressed to the viewer",
        audience: :direct,
        mentions_viewer: true,
        relationship: :none,
        # A DM addressed to the viewer does raise a mention notification, because
        # the viewer is in `to`.
        expected: :visible,
        gaps: [],
        only: [:object_visibility, :home_timeline, :notifications]
      },
      %{
        id: :direct_to_third_party,
        description: "a direct message addressed to somebody else",
        audience: :direct,
        mentions_viewer: false,
        relationship: :none,
        expected: :hidden,
        gaps: []
      },

      # ---- viewer blocks author: hide everywhere, both directions ----
      %{
        id: :public_viewer_blocks_author,
        description: "a public post from an author the viewer blocks",
        audience: :public,
        mentions_viewer: false,
        relationship: :viewer_blocks_author,
        expected: :hidden,
        gaps: [:object_visibility, :public_timeline],
        only: [:object_visibility, :public_timeline, :home_timeline]
      },
      %{
        id: :mention_viewer_blocks_author,
        description: "a post mentioning the viewer from an author they block",
        audience: :public,
        mentions_viewer: true,
        relationship: :viewer_blocks_author,
        expected: :hidden,
        gaps: [:object_visibility, :public_timeline, :notifications]
      },

      # ---- author blocks viewer: the incoming direction ----
      %{
        id: :public_author_blocks_viewer,
        description: "a public post from an author who blocks the viewer",
        audience: :public,
        mentions_viewer: false,
        relationship: :author_blocks_viewer,
        expected: :hidden,
        # `:home_timeline` is absent from `:gaps`, so it conforms — but only
        # incidentally. No moderation filter looks at the incoming direction of a
        # block; the post is missing from home because blocking severs the follow,
        # and an unfollowed author's plain post was never in home to begin with.
        # Stop severing follows and this leaks, with no filter to catch it.
        gaps: [:object_visibility, :public_timeline],
        only: [:object_visibility, :public_timeline, :home_timeline]
      },

      # ---- viewer mutes author: hide from feeds, keep reachable ----
      %{
        id: :public_viewer_mutes_author,
        description: "a public post from an author the viewer mutes",
        audience: :public,
        mentions_viewer: false,
        relationship: :viewer_mutes_author,
        expected: :hidden,
        # A mute is weaker than a block: it silences feeds without making the
        # content unreachable, so this surface is correct as-is.
        expected_per_surface: %{object_visibility: :visible},
        gaps: [:public_timeline],
        only: [:object_visibility, :public_timeline, :home_timeline]
      },
      %{
        id: :mention_viewer_mutes_author,
        description: "a post mentioning the viewer from an author they mute",
        audience: :public,
        mentions_viewer: true,
        relationship: :viewer_mutes_author,
        expected: :hidden,
        expected_per_surface: %{object_visibility: :visible},
        gaps: [:public_timeline, :notifications]
      }
    ]
  end

  @doc "Cases meaningful for a surface."
  def cases_for(surface) when surface in @surfaces do
    Enum.filter(cases(), fn c -> surface in Map.get(c, :only, @surfaces) end)
  end

  @doc """
  What a surface should return for a case, and whether that is a known gap.

  Returns `{:visible | :hidden, :conforms | :known_gap}`. When the second element
  is `:known_gap`, the first is the *current* behavior, which is the opposite of
  the intent.
  """
  def outcome_for(test_case, surface) do
    intended =
      test_case
      |> Map.get(:expected_per_surface, %{})
      |> Map.get(surface, test_case.expected)

    if surface in test_case.gaps do
      {invert(intended), :known_gap}
    else
      {intended, :conforms}
    end
  end

  defp invert(:visible), do: :hidden
  defp invert(:hidden), do: :visible
end
