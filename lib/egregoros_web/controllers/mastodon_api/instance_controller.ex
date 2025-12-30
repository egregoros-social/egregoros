defmodule EgregorosWeb.MastodonAPI.InstanceController do
  use EgregorosWeb, :controller

  import Ecto.Query, only: [from: 2]

  alias Egregoros.Object
  alias Egregoros.Repo
  alias Egregoros.User
  alias EgregorosWeb.Endpoint

  @weeks_of_activity 12

  def show(conn, _params) do
    base_url = Endpoint.url()
    host = URI.parse(base_url).host || "localhost"

    user_count = Repo.aggregate(User, :count, :id)

    status_count =
      from(o in Object, where: o.type == "Note")
      |> Repo.aggregate(:count, :id)

    json(conn, %{
      "uri" => host,
      "title" => "Egregoros",
      "short_description" => "A reduced federation core with an opinionated UI.",
      "description" => "A reduced federation core with an opinionated UI.",
      "email" => nil,
      "version" => "egregoros/#{app_version()}",
      "urls" => %{"streaming_api" => streaming_url(base_url)},
      "stats" => %{
        "user_count" => user_count,
        "status_count" => status_count,
        "domain_count" => 0
      },
      "thumbnail" => nil,
      "languages" => ["en"],
      "registrations" => true,
      "approval_required" => false,
      "invites_enabled" => false
    })
  end

  def peers(conn, _params) do
    json(conn, [])
  end

  def activity(conn, _params) do
    today = Date.utc_today()

    activity =
      0..(@weeks_of_activity - 1)
      |> Enum.map(fn weeks_ago ->
        start_date = Date.add(today, -(6 + weeks_ago * 7))
        end_date = Date.add(start_date, 6)
        start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
        end_dt = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")

        %{
          "week" => start_dt |> DateTime.to_unix() |> Integer.to_string(),
          "statuses" => start_dt |> count_local_statuses(end_dt) |> Integer.to_string(),
          "logins" => "0",
          "registrations" => start_dt |> count_local_registrations(end_dt) |> Integer.to_string()
        }
      end)

    json(conn, activity)
  end

  def show_v2(conn, _params) do
    base_url = Endpoint.url()
    host = URI.parse(base_url).host || "localhost"

    active_month = Repo.aggregate(User, :count, :id)

    json(conn, %{
      "domain" => host,
      "title" => "Egregoros",
      "version" => "egregoros/#{app_version()}",
      "source_url" => nil,
      "description" => "A reduced federation core with an opinionated UI.",
      "usage" => %{
        "users" => %{
          "active_month" => active_month
        }
      },
      "thumbnail" => nil,
      "languages" => ["en"],
      "configuration" => %{
        "urls" => %{
          "streaming" => streaming_url(base_url)
        },
        "statuses" => %{
          "max_characters" => 5000,
          "max_media_attachments" => 4,
          "characters_reserved_per_url" => 23
        },
        "media_attachments" => %{
          "supported_mime_types" => supported_mime_types(),
          "image_size_limit" => 10_000_000,
          "image_matrix_limit" => 16_777_216,
          "video_size_limit" => 40_000_000,
          "video_frame_rate_limit" => 60,
          "video_matrix_limit" => 16_777_216
        },
        "polls" => %{
          "max_options" => 4,
          "max_characters_per_option" => 50,
          "min_expiration" => 300,
          "max_expiration" => 2_592_000
        }
      },
      "registrations" => %{
        "enabled" => true,
        "approval_required" => false,
        "message" => nil
      },
      "contact" => %{
        "email" => nil,
        "account" => nil
      },
      "rules" => []
    })
  end

  defp app_version do
    case Application.spec(:egregoros, :vsn) do
      nil -> "0.0.0"
      vsn -> to_string(vsn)
    end
  end

  defp streaming_url(base_url) when is_binary(base_url) do
    base_url
    |> String.replace_prefix("https://", "wss://")
    |> String.replace_prefix("http://", "ws://")
  end

  defp supported_mime_types do
    [
      "image/jpeg",
      "image/png",
      "image/gif",
      "image/webp",
      "image/heic",
      "video/mp4",
      "video/webm",
      "audio/mpeg",
      "audio/mp4",
      "audio/ogg",
      "audio/webm",
      "audio/wav",
      "application/ogg"
    ]
  end

  defp count_local_statuses(%DateTime{} = start_dt, %DateTime{} = end_dt) do
    from(o in Object,
      where:
        o.type == "Note" and o.local == true and not is_nil(o.published) and o.published >= ^start_dt and
          o.published <= ^end_dt
    )
    |> Repo.aggregate(:count, :id)
  end

  defp count_local_registrations(%DateTime{} = start_dt, %DateTime{} = end_dt) do
    from(u in User,
      where: u.local == true and u.inserted_at >= ^start_dt and u.inserted_at <= ^end_dt
    )
    |> Repo.aggregate(:count, :id)
  end
end
