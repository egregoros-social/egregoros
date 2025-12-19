defmodule PleromaReduxWeb.WebFingerController do
  use PleromaReduxWeb, :controller

  alias PleromaRedux.Users
  alias PleromaReduxWeb.Endpoint

  def webfinger(conn, %{"resource" => resource}) do
    host = Endpoint.url() |> URI.parse() |> Map.fetch!(:host)

    case find_user(resource, host) do
      nil ->
        send_resp(conn, 404, "Not Found")

      user ->
        conn
        |> put_resp_content_type("application/jrd+json")
        |> json(%{
          "subject" => "acct:#{user.nickname}@#{host}",
          "aliases" => [user.ap_id],
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

  defp find_user(resource, host) do
    regex = ~r/^(acct:)?(?<username>[^@]+)@#{Regex.escape(host)}$/

    case Regex.named_captures(regex, resource || "") do
      %{"username" => username} ->
        Users.get_by_nickname(username)

      _ ->
        Users.get_by_ap_id(resource)
    end
  end
end
