defmodule EgregorosWeb.WebFingerController do
  use EgregorosWeb, :controller

  alias Egregoros.Domain
  alias Egregoros.Federation.InstanceActor
  alias Egregoros.User
  alias Egregoros.Users
  alias Egregoros.VerifiableCredentials.DidWeb
  alias EgregorosWeb.Endpoint

  def webfinger(conn, %{"resource" => resource}) do
    base_uri = URI.parse(Endpoint.url())

    canonical_domain =
      case Domain.from_uri(base_uri) do
        domain when is_binary(domain) and domain != "" -> domain
        _ -> base_uri.host || "localhost"
      end

    local_domains = Domain.aliases_from_uri(base_uri)

    case find_user(resource, local_domains, canonical_domain) do
      nil ->
        send_resp(conn, 404, "Not Found")

      {user, subject_domain} ->
        subject_domain =
          case subject_domain do
            value when is_binary(value) and value != "" -> value
            _ -> canonical_domain
          end

        aliases =
          [user.ap_id]
          |> maybe_add_did_alias(user)

        conn
        |> put_resp_content_type("application/jrd+json")
        |> json(%{
          "subject" => "acct:#{user.nickname}@#{subject_domain}",
          "aliases" => aliases,
          "links" => [
            %{
              "rel" => "self",
              "type" => "application/activity+json",
              "href" => user.ap_id
            }
          ]
        })
    end
  end

  def webfinger(conn, _params), do: send_resp(conn, 400, "Bad Request")

  defp find_user(resource, local_domains, canonical_domain)
       when is_binary(resource) and is_list(local_domains) and is_binary(canonical_domain) do
    case parse_acct_resource(resource) do
      {:ok, username, domain} ->
        domain = domain |> String.trim() |> String.downcase()

        if domain in local_domains do
          case Users.get_by_nickname(username) do
            nil -> nil
            user -> {user, domain}
          end
        else
          find_user_by_ap_id(resource, canonical_domain)
        end

      :error ->
        find_user_by_ap_id(resource, canonical_domain)
    end
  end

  defp find_user(_resource, _local_domains, _canonical_domain), do: nil

  defp find_user_by_ap_id(resource, canonical_domain) when is_binary(resource) do
    case Users.get_by_ap_id(resource) do
      nil ->
        case maybe_instance_actor_for_did(resource) do
          {:ok, %User{} = user} -> {user, canonical_domain}
          _ -> nil
        end

      user ->
        {user, canonical_domain}
    end
  end

  defp parse_acct_resource(resource) when is_binary(resource) do
    resource = String.trim(resource)

    if resource == "" or String.starts_with?(resource, "http://") or
         String.starts_with?(resource, "https://") do
      :error
    else
      case resource |> String.trim_leading("acct:") |> String.split("@", parts: 2) do
        [username, domain] when username != "" and domain != "" -> {:ok, username, domain}
        _ -> :error
      end
    end
  end

  defp parse_acct_resource(_resource), do: :error

  defp maybe_add_did_alias(aliases, %User{} = user) when is_list(aliases) do
    if instance_actor?(user) do
      case DidWeb.instance_did() do
        did when is_binary(did) and did != "" -> Enum.uniq(aliases ++ [did])
        _ -> aliases
      end
    else
      aliases
    end
  end

  defp maybe_add_did_alias(aliases, _user), do: aliases

  defp maybe_instance_actor_for_did(resource) when is_binary(resource) do
    did = DidWeb.instance_did()

    if is_binary(did) and did != "" and resource == did do
      InstanceActor.get_actor()
    else
      nil
    end
  end

  defp maybe_instance_actor_for_did(_resource), do: nil

  defp instance_actor?(%User{} = user) do
    instance_ap_id = Endpoint.url()
    user.ap_id == instance_ap_id
  end
end
