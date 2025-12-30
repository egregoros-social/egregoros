defmodule Egregoros.CustomEmojisTest do
  use ExUnit.Case, async: true

  alias Egregoros.CustomEmojis

  test "filters unsafe custom emoji URLs" do
    tags = [
      %{
        "type" => "Emoji",
        "name" => ":ok:",
        "icon" => %{"url" => "https://cdn.example/ok.png"}
      },
      %{
        "type" => "Emoji",
        "name" => ":loopback:",
        "icon" => %{"url" => "http://127.0.0.1/emoji.png"}
      },
      %{
        "type" => "Emoji",
        "name" => ":js:",
        "icon" => %{"url" => "javascript:alert(1)"}
      }
    ]

    assert [%{shortcode: "ok", url: "https://cdn.example/ok.png"}] =
             CustomEmojis.from_activity_tags(tags)
  end
end

