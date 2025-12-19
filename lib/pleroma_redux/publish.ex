defmodule PleromaRedux.Publish do
  alias PleromaRedux.Activities.Create
  alias PleromaRedux.Activities.Note
  alias PleromaRedux.Pipeline
  alias PleromaRedux.User

  def post_note(%User{} = user, content) when is_binary(content) do
    post_note(user, content, [])
  end

  def post_note(%User{} = user, content, opts) when is_binary(content) and is_list(opts) do
    content = String.trim(content)
    attachments = Keyword.get(opts, :attachments, [])

    if content == "" do
      {:error, :empty}
    else
      note =
        user
        |> Note.build(content)
        |> maybe_put_attachments(attachments)

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
end
