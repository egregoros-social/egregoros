defmodule EgregorosWeb.MastodonAPI.AccountRenderer do
  alias Egregoros.Domain
  alias Egregoros.HTML
  alias Egregoros.Objects
  alias Egregoros.Relationships
  alias Egregoros.SafeURL
  alias Egregoros.User
  alias EgregorosWeb.ProfilePaths
  alias EgregorosWeb.URL

  def render_account(%User{} = user), do: render_account(user, [])

  def render_account(%{ap_id: ap_id, nickname: nickname}) do
    url =
      case ProfilePaths.profile_path(ap_id) do
        path when is_binary(path) and path != "" -> URL.absolute(path)
        _ -> ap_id
      end

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
      "url" => url
    }
  end

  def render_account(_), do: %{"id" => "unknown", "username" => "unknown", "acct" => "unknown"}

  def render_account(%User{} = user, opts) when is_list(opts) do
    avatar_url = URL.absolute(user.avatar_url, user.ap_id) || ""

    url =
      case ProfilePaths.profile_path(user) do
        path when is_binary(path) and path != "" -> URL.absolute(path)
        _ -> user.ap_id
      end

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
      "emojis" => emojis(user),
      "fields" => [],
      "source" => %{
        "note" => user.bio || "",
        "fields" => [],
        "privacy" => "public",
        "sensitive" => false,
        "language" => nil
      },
      "url" => url
    }
  end

  defp acct(%User{local: true, nickname: nickname}) when is_binary(nickname), do: nickname

  defp acct(%User{local: false, nickname: nickname, domain: domain})
       when is_binary(nickname) and is_binary(domain) and domain != "" do
    "#{nickname}@#{domain}"
  end

  defp acct(%User{nickname: nickname, ap_id: ap_id})
       when is_binary(nickname) and is_binary(ap_id) do
    case Domain.from_uri(URI.parse(ap_id)) do
      domain when is_binary(domain) and domain != "" -> "#{nickname}@#{domain}"
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

  defp emojis(%User{} = user) do
    user
    |> Map.get(:emojis, [])
    |> List.wrap()
    |> Enum.map(&render_custom_emoji(user, &1))
    |> Enum.filter(&is_map/1)
  end

  defp emojis(_), do: []

  defp render_custom_emoji(%User{} = user, %{shortcode: shortcode, url: url}) do
    render_custom_emoji(user, %{"shortcode" => shortcode, "url" => url})
  end

  defp render_custom_emoji(%User{} = user, %{"shortcode" => shortcode, "url" => url})
       when is_binary(shortcode) and is_binary(url) do
    shortcode =
      shortcode
      |> String.trim()
      |> String.trim(":")

    url = resolve_url(url, user.ap_id)

    if shortcode != "" and is_binary(url) and SafeURL.validate_http_url_no_dns(url) == :ok do
      %{
        "shortcode" => shortcode,
        "url" => url,
        "static_url" => url,
        "visible_in_picker" => false
      }
    end
  end

  defp render_custom_emoji(_user, _emoji), do: nil

  defp resolve_url(url, base) when is_binary(url) and is_binary(base) do
    url = String.trim(url)

    cond do
      url == "" ->
        nil

      String.starts_with?(url, ["http://", "https://"]) ->
        url

      true ->
        case URI.parse(base) do
          %URI{scheme: scheme, host: host}
          when scheme in ["http", "https"] and is_binary(host) and host != "" ->
            base
            |> URI.merge(url)
            |> URI.to_string()

          _ ->
            nil
        end
    end
  end

  defp resolve_url(_url, _base), do: nil
end
