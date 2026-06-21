defmodule EgregorosWeb.BadgeDefinitionController do
  use EgregorosWeb, :controller

  alias Egregoros.BadgeDefinition
  alias Egregoros.Repo
  alias EgregorosWeb.Endpoint
  alias EgregorosWeb.URL

  def show(conn, %{"id" => id}) do
    id = id |> to_string() |> String.trim()

    with true <- flake_id?(id),
         %BadgeDefinition{} = badge <- Repo.get(BadgeDefinition, id) do
      payload = badge_payload(badge)

      conn
      |> put_resp_content_type("application/ld+json")
      |> send_resp(200, Jason.encode!(payload))
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  defp badge_payload(%BadgeDefinition{} = badge) do
    id = Endpoint.url() <> "/badges/" <> badge.id

    %{
      "@context" => [
        "https://www.w3.org/ns/credentials/v2",
        "https://purl.imsglobal.org/spec/ob/v3p0/context-3.0.3.json"
      ],
      "id" => id,
      "type" => "Achievement",
      "name" => badge.name,
      "description" => badge.description,
      "criteria" => %{"narrative" => badge.narrative}
    }
    |> maybe_put_image(badge)
  end

  defp maybe_put_image(payload, %BadgeDefinition{image_url: image_url})
       when is_binary(image_url) and image_url != "" do
    Map.put(payload, "image", %{
      "id" => URL.absolute(image_url),
      "type" => "Image"
    })
  end

  defp maybe_put_image(payload, _badge), do: payload

  defp flake_id?(id) when is_binary(id) do
    id = String.trim(id)
    byte_size(id) == 18 and FlakeId.flake_id?(id)
  end

  defp flake_id?(_id), do: false
end
