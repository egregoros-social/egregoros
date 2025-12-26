defmodule Egregoros.Publish do
  alias Egregoros.Activities.Create
  alias Egregoros.Activities.Note
  alias Egregoros.Federation.Actor
  alias Egregoros.Federation.WebFinger
  alias Egregoros.Mentions
  alias Egregoros.Pipeline
  alias Egregoros.User
  alias Egregoros.Users

  @as_public "https://www.w3.org/ns/activitystreams#Public"
  @max_note_chars 5000

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

    cond do
      content == "" and attachments == [] ->
        {:error, :empty}

      String.length(content) > @max_note_chars ->
        {:error, :too_long}

      true ->
        direct_recipients =
          if visibility == "direct" do
            resolve_direct_recipients(content, user.ap_id)
          else
            []
          end

        note =
          user
          |> Note.build(content)
          |> maybe_put_attachments(attachments)
          |> maybe_put_in_reply_to(in_reply_to)
          |> maybe_put_visibility(visibility, user.ap_id, direct_recipients)
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

  defp maybe_put_visibility(note, visibility, actor, direct_recipients)
       when is_map(note) and is_binary(visibility) and is_binary(actor) do
    followers = actor <> "/followers"

    direct_recipients =
      direct_recipients
      |> List.wrap()
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    {to, cc} =
      case visibility do
        "public" -> {[@as_public], [followers]}
        "unlisted" -> {[followers], [@as_public]}
        "private" -> {[followers], []}
        "direct" -> {direct_recipients, []}
        _ -> {[@as_public], [followers]}
      end

    note
    |> Map.put("to", to)
    |> Map.put("cc", cc)
  end

  defp maybe_put_visibility(note, _visibility, _actor, _direct_recipients), do: note

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

  defp resolve_direct_recipients(content, actor_ap_id)
       when is_binary(content) and is_binary(actor_ap_id) do
    local_domains = local_domains(actor_ap_id)

    content
    |> Mentions.extract()
    |> Enum.reduce([], fn {nickname, host}, acc ->
      case resolve_mention_recipient(nickname, host, local_domains) do
        ap_id when is_binary(ap_id) and ap_id != "" -> [ap_id | acc]
        _ -> acc
      end
    end)
    |> Enum.uniq()
  end

  defp resolve_direct_recipients(_content, _actor_ap_id), do: []

  defp resolve_mention_recipient(nickname, nil, _local_domains) when is_binary(nickname) do
    case Users.get_by_nickname(nickname) do
      %User{ap_id: ap_id} when is_binary(ap_id) -> ap_id
      _ -> nil
    end
  end

  defp resolve_mention_recipient(nickname, host, local_domains)
       when is_binary(nickname) and is_binary(host) and is_list(local_domains) do
    host = host |> String.trim() |> String.downcase()

    if host in local_domains do
      resolve_mention_recipient(nickname, nil, local_domains)
    else
      handle = nickname <> "@" <> host

      case Users.get_by_handle(handle) do
        %User{ap_id: ap_id} when is_binary(ap_id) ->
          ap_id

        _ ->
          with {:ok, actor_url} <- WebFinger.lookup(handle),
               {:ok, %User{ap_id: ap_id}} <- Actor.fetch_and_store(actor_url) do
            ap_id
          else
            _ -> nil
          end
      end
    end
  end

  defp resolve_mention_recipient(_nickname, _host, _local_domains), do: nil

  defp local_domains(actor_ap_id) when is_binary(actor_ap_id) do
    case URI.parse(String.trim(actor_ap_id)) do
      %URI{host: host} when is_binary(host) and host != "" ->
        host = String.downcase(host)

        port =
          case URI.parse(String.trim(actor_ap_id)) do
            %URI{port: port} when is_integer(port) and port > 0 -> port
            _ -> nil
          end

        domains =
          [host, if(is_integer(port), do: host <> ":" <> Integer.to_string(port), else: nil)]
          |> Enum.filter(&is_binary/1)

        Enum.uniq(domains)

      _ ->
        []
    end
  end

  defp local_domains(_actor_ap_id), do: []
end
