defmodule PleromaRedux.Publish do
  alias PleromaRedux.Activities.Create
  alias PleromaRedux.Activities.Note
  alias PleromaRedux.Pipeline
  alias PleromaRedux.User

  @as_public "https://www.w3.org/ns/activitystreams#Public"

  def post_note(%User{} = user, content) when is_binary(content) do
    post_note(user, content, [])
  end

  def post_note(%User{} = user, content, opts) when is_binary(content) and is_list(opts) do
    content = String.trim(content)
    attachments = Keyword.get(opts, :attachments, [])
    in_reply_to = Keyword.get(opts, :in_reply_to)
    visibility = Keyword.get(opts, :visibility, "public")
    spoiler_text = Keyword.get(opts, :spoiler_text)
    sensitive = Keyword.get(opts, :sensitive)
    language = Keyword.get(opts, :language)

    if content == "" and attachments == [] do
      {:error, :empty}
    else
      note =
        user
        |> Note.build(content)
        |> maybe_put_attachments(attachments)
        |> maybe_put_in_reply_to(in_reply_to)
        |> maybe_put_visibility(visibility, user.ap_id)
        |> maybe_put_summary(spoiler_text)
        |> maybe_put_sensitive(sensitive)
        |> maybe_put_language(language)

      create = Create.build(user, note)

      Pipeline.ingest(create, local: true)
    end
  end

  defp maybe_put_attachments(note, attachments) when is_map(note) and is_list(attachments) do
    if attachments == [] do
      note
    else
      Map.put(note, "attachment", attachments)
    end
  end

  defp maybe_put_attachments(note, _attachments), do: note

  defp maybe_put_in_reply_to(note, nil), do: note

  defp maybe_put_in_reply_to(note, in_reply_to) when is_map(note) and is_binary(in_reply_to) do
    Map.put(note, "inReplyTo", in_reply_to)
  end

  defp maybe_put_in_reply_to(note, _in_reply_to), do: note

  defp maybe_put_visibility(note, visibility, actor)
       when is_map(note) and is_binary(visibility) and is_binary(actor) do
    followers = actor <> "/followers"

    {to, cc} =
      case visibility do
        "public" -> {[@as_public], [followers]}
        "unlisted" -> {[followers], [@as_public]}
        "private" -> {[followers], []}
        "direct" -> {[], []}
        _ -> {[@as_public], [followers]}
      end

    note
    |> Map.put("to", to)
    |> Map.put("cc", cc)
  end

  defp maybe_put_visibility(note, _visibility, _actor), do: note

  defp maybe_put_summary(note, value) when is_map(note) and is_binary(value) do
    summary = String.trim(value)

    if summary == "" do
      note
    else
      Map.put(note, "summary", summary)
    end
  end

  defp maybe_put_summary(note, _value), do: note

  defp maybe_put_sensitive(note, value) when is_map(note) do
    case value do
      true -> Map.put(note, "sensitive", true)
      "true" -> Map.put(note, "sensitive", true)
      _ -> note
    end
  end

  defp maybe_put_sensitive(note, _value), do: note

  defp maybe_put_language(note, value) when is_map(note) and is_binary(value) do
    language = String.trim(value)

    if language == "" do
      note
    else
      Map.put(note, "language", language)
    end
  end

  defp maybe_put_language(note, _value), do: note
end
