defmodule PleromaReduxWeb.MastodonAPI.InstanceController do
  use PleromaReduxWeb, :controller

  import Ecto.Query, only: [from: 2]

  alias PleromaRedux.Object
  alias PleromaRedux.Repo
  alias PleromaRedux.User
  alias PleromaReduxWeb.Endpoint

  def show(conn, _params) do
    base_url = Endpoint.url()
    host = URI.parse(base_url).host || "localhost"

    user_count = Repo.aggregate(User, :count, :id)

    status_count =
      from(o in Object, where: o.type == "Note")
      |> Repo.aggregate(:count, :id)

    json(conn, %{
      "uri" => host,
      "title" => "Pleroma Redux",
      "short_description" => "A reduced federation core with an opinionated UI.",
      "description" => "A reduced federation core with an opinionated UI.",
      "email" => nil,
      "version" => "pleroma_redux/#{app_version()}",
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

  def show_v2(conn, _params) do
    base_url = Endpoint.url()
    host = URI.parse(base_url).host || "localhost"

    active_month = Repo.aggregate(User, :count, :id)

    json(conn, %{
      "domain" => host,
      "title" => "Pleroma Redux",
      "version" => "pleroma_redux/#{app_version()}",
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
    case Application.spec(:pleroma_redux, :vsn) do
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
end
