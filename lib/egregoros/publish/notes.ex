defmodule Egregoros.Publish.Notes do
  @moduledoc """
  Note-specific publish operations.

  Handles posting notes and related operations for ActivityPub Note objects.
  """

  alias Egregoros.Activities.Create
  alias Egregoros.Activities.Note
  alias Egregoros.HTML
  alias Egregoros.Pipeline
  alias Egregoros.Publish.PostBuilder
  alias Egregoros.User

  @max_note_chars 5000

  @doc """
  Post a note with default options.

  ## Parameters
  - `user` - The user posting the note
  - `content` - The text content of the note

  ## Returns
  - `{:ok, create_activity}` on success
  - `{:error, reason}` on failure
  """
  def post_note(%User{} = user, content) when is_binary(content) do
    post_note(user, content, [])
  end

  @doc """
  Post a note with options.

  ## Parameters
  - `user` - The user posting the note
  - `content` - The text content of the note
  - `opts` - Keyword list of options:
    - `:attachments` - List of media attachments
    - `:in_reply_to` - AP ID of the parent object
    - `:visibility` - One of "public", "unlisted", "private", "direct"
    - `:spoiler_text` - Content warning text
    - `:sensitive` - Whether the post contains sensitive content
    - `:language` - Language code for the post

  ## Returns
  - `{:ok, create_activity}` on success
  - `{:error, reason}` on failure

  ## Error reasons
  - `:empty` - Content is empty and no attachments provided
  - `:too_long` - Content exceeds maximum character limit
  """
  def post_note(%User{} = user, content, opts) when is_binary(content) and is_list(opts) do
    content = String.trim(content)
    attachments = Keyword.get(opts, :attachments, [])
    in_reply_to = Keyword.get(opts, :in_reply_to)
    visibility = Keyword.get(opts, :visibility, "public")
    spoiler_text = Keyword.get(opts, :spoiler_text)
    sensitive = Keyword.get(opts, :sensitive)
    language = Keyword.get(opts, :language)

    cond do
      content == "" and attachments == [] ->
        {:error, :empty}

      String.length(content) > @max_note_chars ->
        {:error, :too_long}

      true ->
        {mentions, unresolved_remote_mentions} = PostBuilder.resolve_mentions(content, user.ap_id)
        reply_mentions = PostBuilder.resolve_reply_mentions(in_reply_to, user.ap_id)

        mentions =
          (mentions ++ reply_mentions)
          |> Enum.filter(&is_map/1)
          |> Enum.uniq_by(& &1.ap_id)

        mention_recipient_ids = Enum.map(mentions, & &1.ap_id)
        mention_tags = Enum.map(mentions, &PostBuilder.mention_tag/1)
        hashtag_tags = PostBuilder.hashtag_tags(content)
        mention_hrefs = PostBuilder.mention_hrefs(mentions)

        content_html = HTML.to_safe_html(content, format: :text, mention_hrefs: mention_hrefs)

        note =
          user
          |> Note.build(content_html)
          |> Map.put("source", %{"content" => content, "mediaType" => "text/plain"})
          |> PostBuilder.put_attachments(attachments)
          |> PostBuilder.put_in_reply_to(in_reply_to)
          |> PostBuilder.put_visibility(visibility, user.ap_id, mention_recipient_ids)
          |> PostBuilder.put_tags(mention_tags ++ hashtag_tags)
          |> PostBuilder.put_summary(spoiler_text)
          |> PostBuilder.put_sensitive(sensitive)
          |> PostBuilder.put_language(language)

        create = Create.build(user, note)

        ingest_opts =
          if unresolved_remote_mentions == [] do
            [local: true]
          else
            [local: true, deliver: false]
          end

        with {:ok, create_object} <- Pipeline.ingest(create, ingest_opts) do
          if unresolved_remote_mentions != [] do
            _ =
              Oban.insert(
                Egregoros.Workers.ResolveMentions.new(%{
                  "create_ap_id" => create_object.ap_id,
                  "remote_mentions" => unresolved_remote_mentions
                })
              )
          end

          {:ok, create_object}
        end
    end
  end
end
