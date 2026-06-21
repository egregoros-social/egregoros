defmodule Egregoros.Federation.Actor do
  alias Egregoros.CustomEmojis
  alias Egregoros.Domain
  alias Egregoros.HTTP
  alias Egregoros.Federation.SignedFetch
  alias Egregoros.SafeURL
  alias Egregoros.UserEvents
  alias Egregoros.Users

  def fetch_and_store(actor_url) when is_binary(actor_url) do
    with :ok <- SafeURL.validate_http_url_federation(actor_url),
         {:ok, actor} <- fetch_actor(actor_url),
         {:ok, attrs} <- to_user_attrs(actor, actor_url),
         {:ok, user} <- Users.upsert_user(attrs) do
      _ = UserEvents.broadcast_update(user.ap_id)
      {:ok, user}
    else
      {:error, _} = error -> error
      _ -> {:error, :actor_fetch_failed}
    end
  end

  def fetch_and_store_with_counts(actor_url) when is_binary(actor_url) do
    checked_at = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    with :ok <- SafeURL.validate_http_url_federation(actor_url),
         {:ok, actor} <- fetch_actor(actor_url),
         {:ok, attrs} <- to_user_attrs(actor, actor_url) do
      count_attrs =
        actor
        |> fetch_follow_counts(actor_url)
        |> Map.put(:remote_counts_checked_at, checked_at)

      attrs =
        attrs
        |> Map.merge(count_attrs)

      Users.upsert_user(attrs)
    else
      {:error, _} = error -> error
      _ -> {:error, :actor_fetch_failed}
    end
  end

  def upsert_from_map(%{} = actor) do
    actor_url = actor |> extract_id() |> normalize_id()

    with actor_url when is_binary(actor_url) and actor_url != "" <- actor_url,
         :ok <- SafeURL.validate_http_url_federation(actor_url),
         {:ok, attrs} <- to_user_attrs(actor, actor_url),
         {:ok, user} <- Users.upsert_user(attrs) do
      _ = UserEvents.broadcast_update(user.ap_id)
      {:ok, user}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_actor}
    end
  end

  def upsert_from_map(_actor), do: {:error, :invalid_actor}

  defp fetch_actor(actor_url) when is_binary(actor_url) do
    case HTTP.get(actor_url, headers()) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        with {:ok, actor} <- decode_json(body) do
          actor =
            if sparse_actor?(actor) or missing_endpoints?(actor) do
              case fetch_actor_signed(actor_url) do
                {:ok, signed_actor} -> signed_actor
                _ -> actor
              end
            else
              actor
            end

          {:ok, actor}
        end

      {:ok, %{status: status}} when status in [401, 403] ->
        fetch_actor_signed(actor_url)

      {:ok, _response} ->
        {:error, :actor_fetch_failed}

      {:error, _} = error ->
        error
    end
  end

  defp fetch_actor_signed(actor_url) when is_binary(actor_url) do
    with {:ok, %{status: status, body: body}} when status in 200..299 <-
           SignedFetch.get(actor_url, accept: "application/activity+json, application/ld+json"),
         {:ok, actor} <- decode_json(body) do
      {:ok, actor}
    else
      {:error, _} = error -> error
      _ -> {:error, :actor_fetch_failed}
    end
  end

  defp sparse_actor?(actor) when is_map(actor) do
    allowed_keys = MapSet.new(["@context", "id", "publicKey"])

    actor
    |> Map.keys()
    |> Enum.all?(&MapSet.member?(allowed_keys, &1))
  end

  defp sparse_actor?(_), do: false

  defp missing_endpoints?(actor) when is_map(actor) do
    has_required_id_and_key?(actor) and not has_endpoints?(actor)
  end

  defp missing_endpoints?(_), do: false

  defp has_required_id_and_key?(actor) when is_map(actor) do
    id = Map.get(actor, "id")
    public_key = get_in(actor, ["publicKey", "publicKeyPem"])

    is_binary(id) and String.trim(id) != "" and is_binary(public_key) and
      String.trim(public_key) != ""
  end

  defp has_required_id_and_key?(_), do: false

  defp has_endpoints?(actor) when is_map(actor) do
    inbox = Map.get(actor, "inbox")
    outbox = Map.get(actor, "outbox")

    is_binary(inbox) and String.trim(inbox) != "" and is_binary(outbox) and
      String.trim(outbox) != ""
  end

  defp has_endpoints?(_), do: false

  defp headers do
    [
      {"accept", "application/activity+json, application/ld+json"},
      {"user-agent", "egregoros"}
    ]
  end

  defp decode_json(body) when is_map(body), do: {:ok, body}

  defp decode_json(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      _ -> {:error, :invalid_json}
    end
  end

  defp decode_json(_), do: {:error, :invalid_json}

  defp fetch_follow_counts(%{} = actor, actor_id) when is_binary(actor_id) do
    actor_id = String.trim(actor_id)

    followers =
      actor
      |> Map.get("followers")
      |> extract_url()
      |> resolve_url(actor_id)

    following =
      actor
      |> Map.get("following")
      |> extract_url()
      |> resolve_url(actor_id)

    %{}
    |> maybe_put_count(:remote_followers_count, fetch_total_items(followers))
    |> maybe_put_count(:remote_following_count, fetch_total_items(following))
  end

  defp fetch_follow_counts(_actor, _actor_id), do: %{}

  defp maybe_put_count(attrs, key, count) when is_map(attrs) and is_atom(key) do
    if is_integer(count) and count >= 0 do
      Map.put(attrs, key, count)
    else
      attrs
    end
  end

  defp fetch_total_items(url) when is_binary(url) do
    url = String.trim(url)

    with true <- url != "",
         :ok <- SafeURL.validate_http_url_federation(url) do
      case HTTP.get(url, headers()) do
        {:ok, %{status: status, body: body}} when status in 200..299 ->
          with {:ok, %{} = collection} <- decode_json(body) do
            total_items(collection)
          else
            _ -> nil
          end

        {:ok, %{status: status}} when status in [401, 403] ->
          fetch_total_items_signed(url)

        _ ->
          nil
      end
    else
      _ -> nil
    end
  end

  defp fetch_total_items(_url), do: nil

  defp fetch_total_items_signed(url) when is_binary(url) do
    with {:ok, %{status: status, body: body}} when status in 200..299 <-
           SignedFetch.get(url, accept: "application/activity+json, application/ld+json"),
         {:ok, %{} = collection} <- decode_json(body) do
      total_items(collection)
    else
      _ -> nil
    end
  end

  defp total_items(%{} = collection) do
    case Map.get(collection, "totalItems") do
      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(String.trim(value)) do
          {int, ""} -> int
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp total_items(_collection), do: nil

  defp to_user_attrs(%{"id" => id} = actor, actor_url)
       when is_binary(id) and is_binary(actor_url) do
    if id != actor_url do
      {:error, :actor_id_mismatch}
    else
      to_user_attrs_from_id(actor, id)
    end
  end

  defp to_user_attrs(%{"id" => id} = actor, _actor_url) when is_binary(id) do
    to_user_attrs_from_id(actor, id)
  end

  defp to_user_attrs(_actor, _actor_url), do: {:error, :invalid_actor}

  defp extract_id(%{"id" => id}) when is_binary(id), do: id
  defp extract_id(%{id: id}) when is_binary(id), do: id
  defp extract_id(_actor), do: nil

  defp normalize_id(nil), do: nil

  defp normalize_id(id) when is_binary(id) do
    String.trim(id)
  end

  defp normalize_id(_id), do: nil

  defp to_user_attrs_from_id(%{} = actor, id) when is_binary(id) do
    public_key = get_in(actor, ["publicKey", "publicKeyPem"])

    if not is_binary(public_key) or public_key == "" do
      {:error, :missing_public_key}
    else
      with {:ok, inbox} <- required_string_field(actor, "inbox", :missing_inbox),
           {:ok, outbox} <- required_string_field(actor, "outbox", :missing_outbox),
           :ok <- SafeURL.validate_http_url_federation(inbox),
           :ok <- SafeURL.validate_http_url_federation(outbox) do
        domain =
          case URI.parse(id) do
            %URI{} = uri -> Domain.from_uri(uri)
            _ -> nil
          end

        nickname =
          actor
          |> Map.get("preferredUsername")
          |> case do
            value when is_binary(value) and value != "" -> value
            _ -> id |> URI.parse() |> Map.get(:path) |> fallback_nickname()
          end

        attrs = %{
          nickname: nickname,
          domain: domain,
          ap_id: id,
          inbox: inbox,
          outbox: outbox,
          public_key: public_key,
          private_key: nil,
          local: false,
          locked: locked?(actor)
        }

        attrs =
          attrs
          |> maybe_put_string(:name, Map.get(actor, "name"))
          |> maybe_put_string(:bio, Map.get(actor, "summary"))
          |> maybe_put_icon(actor, id)
          |> maybe_put_image(actor, id)
          |> maybe_put_emojis(actor, id)
          |> maybe_put_moved_to(actor, id)
          |> maybe_put_also_known_as(actor, id)
          |> maybe_put_assertion_method(actor)

        {:ok, attrs}
      end
    end
  end

  defp required_string_field(map, key, error)
       when is_map(map) and is_binary(key) and is_atom(error) do
    case Map.get(map, key) do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: {:error, error}, else: {:ok, value}

      _ ->
        {:error, error}
    end
  end

  defp fallback_nickname(nil), do: "unknown"

  defp fallback_nickname(path) when is_binary(path) do
    path
    |> String.split("/", trim: true)
    |> List.last()
    |> case do
      nil -> "unknown"
      value -> value
    end
  end

  defp maybe_put_string(attrs, key, value)
       when is_map(attrs) and is_atom(key) and is_binary(value) do
    value = String.trim(value)
    if value == "", do: attrs, else: Map.put(attrs, key, value)
  end

  defp maybe_put_string(attrs, _key, _value), do: attrs

  defp maybe_put_icon(attrs, actor, actor_id) when is_map(attrs) and is_map(actor) do
    case icon_url(actor, actor_id) do
      url when is_binary(url) and url != "" -> Map.put(attrs, :avatar_url, url)
      _ -> attrs
    end
  end

  defp maybe_put_icon(attrs, _actor, _actor_id), do: attrs

  defp maybe_put_image(attrs, actor, actor_id) when is_map(attrs) and is_map(actor) do
    case image_url(actor, actor_id) do
      url when is_binary(url) and url != "" -> Map.put(attrs, :banner_url, url)
      _ -> attrs
    end
  end

  defp maybe_put_image(attrs, _actor, _actor_id), do: attrs

  defp maybe_put_emojis(attrs, actor, actor_id) when is_map(attrs) and is_map(actor) do
    emojis =
      actor
      |> Map.get("tag", [])
      |> CustomEmojis.from_activity_tags()
      |> Enum.map(fn
        %{shortcode: shortcode, url: url} ->
          %{shortcode: shortcode, url: resolve_url(url, actor_id)}

        %{"shortcode" => shortcode, "url" => url} ->
          %{"shortcode" => shortcode, "url" => resolve_url(url, actor_id)}

        other ->
          other
      end)
      |> Enum.filter(fn
        %{shortcode: shortcode, url: url} when is_binary(shortcode) and is_binary(url) ->
          shortcode = String.trim(shortcode)
          url = String.trim(url)

          shortcode != "" and url != "" and SafeURL.validate_http_url_no_dns(url) == :ok

        %{"shortcode" => shortcode, "url" => url} when is_binary(shortcode) and is_binary(url) ->
          shortcode = String.trim(shortcode)
          url = String.trim(url)

          shortcode != "" and url != "" and SafeURL.validate_http_url_no_dns(url) == :ok

        _ ->
          false
      end)

    if emojis == [] do
      attrs
    else
      Map.put(attrs, :emojis, emojis)
    end
  end

  defp maybe_put_emojis(attrs, _actor, _actor_id), do: attrs

  defp maybe_put_moved_to(attrs, actor, actor_id) when is_map(attrs) and is_map(actor) do
    moved_to_ap_id =
      actor
      |> Map.get("movedTo")
      |> actor_id_value()
      |> resolve_url(actor_id)

    case moved_to_ap_id do
      ap_id when is_binary(ap_id) and ap_id != "" ->
        case SafeURL.validate_http_url_no_dns(ap_id) do
          :ok -> Map.put(attrs, :moved_to_ap_id, ap_id)
          _ -> attrs
        end

      _ ->
        attrs
    end
  end

  defp maybe_put_moved_to(attrs, _actor, _actor_id), do: attrs

  defp maybe_put_also_known_as(attrs, actor, actor_id) when is_map(attrs) and is_map(actor) do
    also_known_as =
      actor
      |> Map.get("alsoKnownAs")
      |> List.wrap()
      |> Enum.flat_map(fn item ->
        id = item |> actor_id_value() |> resolve_url(actor_id)

        case id do
          ap_id when is_binary(ap_id) and ap_id != "" ->
            case SafeURL.validate_http_url_no_dns(ap_id) do
              :ok -> [ap_id]
              _ -> []
            end

          _ ->
            []
        end
      end)
      |> Enum.uniq()

    if also_known_as == [] do
      attrs
    else
      Map.put(attrs, :also_known_as, also_known_as)
    end
  end

  defp maybe_put_also_known_as(attrs, _actor, _actor_id), do: attrs

  defp maybe_put_assertion_method(attrs, actor) when is_map(attrs) and is_map(actor) do
    assertion_method = Map.get(actor, "assertionMethod") || Map.get(actor, "verificationMethod")

    case assertion_method do
      nil -> attrs
      value -> Map.put(attrs, :assertion_method, value)
    end
  end

  defp maybe_put_assertion_method(attrs, _actor), do: attrs

  defp locked?(actor) when is_map(actor) do
    case Map.get(actor, "manuallyApprovesFollowers") do
      true -> true
      "true" -> true
      false -> false
      "false" -> false
      _ -> false
    end
  end

  defp locked?(_actor), do: false

  defp icon_url(%{} = actor, actor_id) when is_binary(actor_id) do
    actor
    |> Map.get("icon")
    |> extract_url()
    |> resolve_url(actor_id)
    |> case do
      url when is_binary(url) ->
        case SafeURL.validate_http_url_federation(url) do
          :ok -> url
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp icon_url(_actor, _actor_id), do: nil

  defp image_url(%{} = actor, actor_id) when is_binary(actor_id) do
    actor
    |> Map.get("image")
    |> extract_url()
    |> resolve_url(actor_id)
    |> case do
      url when is_binary(url) ->
        case SafeURL.validate_http_url_federation(url) do
          :ok -> url
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp image_url(_actor, _actor_id), do: nil

  defp extract_url(url) when is_binary(url), do: url
  defp extract_url(%{"href" => href}) when is_binary(href), do: href
  defp extract_url(%{"url" => url}), do: extract_url(url)

  defp extract_url(list) when is_list(list) do
    Enum.find_value(list, &extract_url/1)
  end

  defp extract_url(_), do: nil

  defp actor_id_value(%{"id" => id}) when is_binary(id), do: id
  defp actor_id_value(%{id: id}) when is_binary(id), do: id
  defp actor_id_value(id) when is_binary(id), do: id
  defp actor_id_value(_), do: nil

  defp resolve_url(nil, _base), do: nil

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
