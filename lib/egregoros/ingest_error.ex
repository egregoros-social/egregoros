defmodule Egregoros.IngestError do
  @moduledoc """
  Classification of ingestion failures, and the Oban outcome each class maps to.

  `Egregoros.Pipeline.ingest/2` returns `{:error, reason}` for a wide range of
  situations, from "this activity is malformed" to "we do not hold the object it
  refers to". Without a contract, the worker cannot tell which of those deserve
  a retry, so every failure was discarded — making `IngestActivity`'s
  `max_attempts` inert.

  Three classes:

    * `:permanent` — the activity will never succeed. Discard it. Retrying wastes
      work and, for rejections like `:not_targeted`, would repeat that work on a
      sender's schedule.
    * `:transient` — the failure is about our state or the network, not the
      activity. Return an error so Oban retries within `max_attempts`.
    * `:duplicate` — the work is already done. Report success.

  The mapping is **total**: an unrecognized reason is treated as `:permanent`,
  because discarding with a logged reason is safer than an unbounded retry loop.
  `known_reasons/0` lists what has been classified explicitly, which lets a test
  assert the ingest path stays fully covered.
  """

  @typedoc "How an ingestion failure should be handled."
  @type class :: :permanent | :transient | :duplicate

  # The activity itself is unacceptable, or is not ours to process. More time,
  # more retries, and more state will not change the answer.
  @permanent [
    # not addressed to this inbox, the owner does not follow the actor, and we
    # already hold enough state to be sure. Contrast `:target_unknown`.
    :not_targeted,
    # failed cast/validate
    :invalid,
    # no activity module claims this type
    :unknown_type,
    # a remote activity claiming a local ActivityPub id (impersonation guard)
    :local_id,
    # the voter is outside the Question's audience
    :voter_not_permitted,
    # content exceeds the accepted length
    :too_long
  ]

  # The activity may well be acceptable; we just could not act on it yet. These
  # are all ordering races: federation_incoming runs concurrently, so an activity
  # can be processed before the one it refers to.
  @transient [
    # an Undo whose target activity we have not ingested yet. Discarding this
    # leaves the Like/Announce/Follow applied forever.
    :target_unknown,
    # an Answer for a Question we do not hold. The Question may arrive from its
    # own job, or from thread completion triggered by another reply.
    :question_not_found
  ]

  # Duplicate ingestion currently succeeds through upsert and returns
  # `{:ok, object}`, so no reason lands here yet. The class exists because
  # `outcome/2` has to answer for it once ingestion tracks completion explicitly.
  @duplicate []

  @doc """
  Classify an ingestion failure reason.

  Unrecognized reasons are `:permanent` — see the module docs.
  """
  @spec classify(term()) :: class()
  # A changeset here is a failed *write*, not a failed validation — cast/validate
  # failures were already mapped to `:invalid` upstream. The common case is a
  # unique `ap_id` violation where the concurrent row is not visible yet, so
  # retrying is right; a genuinely invalid write just exhausts max_attempts.
  def classify(%Ecto.Changeset{}), do: :transient

  def classify(reason) when is_atom(reason) do
    cond do
      reason in @permanent -> :permanent
      reason in @transient -> :transient
      true -> :permanent
    end
  end

  def classify(_reason), do: :permanent

  @doc """
  Every reason with an explicit classification.

  A reason outside this set still has an outcome — `classify/1` is total — but it
  reached the worker without anyone deciding what it means, which is worth
  logging and worth failing a test over.
  """
  @spec known_reasons() :: [atom()]
  def known_reasons, do: @permanent ++ @transient ++ @duplicate

  @doc """
  The Oban outcome for a class.
  """
  @spec outcome(class(), term()) :: :ok | {:error, term()} | {:discard, term()}
  def outcome(:permanent, reason), do: {:discard, reason}
  def outcome(:transient, reason), do: {:error, reason}
  def outcome(:duplicate, _reason), do: :ok

  @doc """
  The Oban outcome for an ingestion failure reason.
  """
  @spec oban_outcome(term()) :: :ok | {:error, term()} | {:discard, term()}
  def oban_outcome(reason), do: outcome(classify(reason), reason)
end
