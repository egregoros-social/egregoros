defmodule PleromaReduxWeb.MastodonAPI.AccountRenderer do
  alias PleromaRedux.HTML
  alias PleromaRedux.Objects
  alias PleromaRedux.Relationships
  alias PleromaRedux.User
  alias PleromaReduxWeb.URL

  def render_account(%User{} = user), do: render_account(user, [])

  def render_account(%{ap_id: ap_id, nickname: nickname}) do
    %{
      "id" => ap_id,
      "username" => nickname,
      "acct" => nickname,
      "display_name" => nickname,
      "note" => "",
      "avatar" => "",
      "avatar_static" => "",
      "header" => "",
      "header_static" => "",
      "locked" => false,
      "bot" => false,
      "discoverable" => true,
      "group" => false,
      "created_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "followers_count" => 0,
      "following_count" => 0,
      "statuses_count" => 0,
      "last_status_at" => nil,
      "emojis" => [],
      "fields" => [],
      "url" => ap_id
    }
  end

  def render_account(_), do: %{"id" => "unknown", "username" => "unknown", "acct" => "unknown"}

  def render_account(%User{} = user, opts) when is_list(opts) do
    avatar_url = URL.absolute(user.avatar_url, user.ap_id) || ""

    bio =
      HTML.to_safe_html(user.bio || "",
        format: if(user.local, do: :text, else: :html)
      )

    followers_count =
      case Keyword.fetch(opts, :followers_count) do
        {:ok, count} when is_integer(count) and count >= 0 -> count
        _ -> Relationships.count_by_type_object("Follow", user.ap_id)
      end

    following_count =
      case Keyword.fetch(opts, :following_count) do
        {:ok, count} when is_integer(count) and count >= 0 -> count
        _ -> Relationships.count_by_type_actor("Follow", user.ap_id)
      end

    statuses_count =
      case Keyword.fetch(opts, :statuses_count) do
        {:ok, count} when is_integer(count) and count >= 0 -> count
        _ -> Objects.count_notes_by_actor(user.ap_id)
      end

    %{
      "id" => Integer.to_string(user.id),
      "username" => user.nickname,
      "acct" => acct(user),
      "display_name" => user.name || user.nickname,
      "note" => bio,
      "avatar" => avatar_url,
      "avatar_static" => avatar_url,
      "header" => "",
      "header_static" => "",
      "locked" => false,
      "bot" => false,
      "discoverable" => true,
      "group" => false,
      "created_at" => format_datetime(user.inserted_at),
      "followers_count" => followers_count,
      "following_count" => following_count,
      "statuses_count" => statuses_count,
      "last_status_at" => nil,
      "emojis" => [],
      "fields" => [],
      "source" => %{
        "note" => user.bio || "",
        "fields" => [],
        "privacy" => "public",
        "sensitive" => false,
        "language" => nil
      },
      "url" => user.ap_id
    }
  end

  defp acct(%User{local: true, nickname: nickname}) when is_binary(nickname), do: nickname

  defp acct(%User{nickname: nickname, ap_id: ap_id})
       when is_binary(nickname) and is_binary(ap_id) do
    case URI.parse(ap_id) do
      %{host: host} when is_binary(host) and host != "" -> "#{nickname}@#{host}"
      _ -> nickname
    end
  end

  defp acct(_), do: "unknown"

  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp format_datetime(%NaiveDateTime{} = dt) do
    dt
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601()
  end

  defp format_datetime(_), do: DateTime.utc_now() |> DateTime.to_iso8601()
end
