defmodule PleromaRedux.HTML.Scrubber.Default do
  @moduledoc false

  require FastSanitize.Sanitizer.Meta

  alias FastSanitize.Sanitizer.Meta

  @valid_schemes ["http", "https", "mailto"]
  @valid_image_schemes ["http", "https"]

  Meta.strip_comments()

  Meta.allow_tag_with_uri_attributes(:a, ["href"], @valid_schemes)
  Meta.allow_tag_with_this_attribute_values(:a, "target", ["_blank", "_self", "_top", "_parent"])

  def scrub_attribute(:a, {"class", value}), do: {"class", value}
  def scrub_attribute(:a, {"rel", value}), do: {"rel", value}
  def scrub_attribute(:a, {"title", value}), do: {"title", value}

  def scrub({:a, attributes, children}) do
    attributes =
      attributes
      |> Enum.map(&scrub_attribute(:a, &1))
      |> Enum.reject(&is_nil/1)
      |> ensure_safe_rel()

    {:a, attributes, children}
  end

  defp ensure_safe_rel(attributes) when is_list(attributes) do
    required = ["nofollow", "noopener", "noreferrer"]

    {rel, attributes} = pop_attribute(attributes, "rel")

    tokens =
      rel
      |> List.wrap()
      |> Enum.join(" ")
      |> String.split(~r/\s+/, trim: true)

    tokens =
      Enum.reduce(required, tokens, fn token, acc ->
        if Enum.any?(acc, &(String.downcase(&1) == token)) do
          acc
        else
          acc ++ [token]
        end
      end)

    attributes ++ [{"rel", Enum.join(tokens, " ")}]
  end

  defp pop_attribute(attributes, key) when is_list(attributes) and is_binary(key) do
    {matches, rest} = Enum.split_with(attributes, fn {attr, _value} -> attr == key end)

    value =
      case matches do
        [{^key, value} | _] -> value
        _ -> nil
      end

    {value, rest}
  end

  Meta.allow_tag_with_uri_attributes(:img, ["src"], @valid_image_schemes)
  Meta.allow_tag_with_these_attributes(:img, ["alt", "title", "class", "width", "height"])

  Meta.allow_tag_with_these_attributes(:p, ["class"])
  Meta.allow_tag_with_these_attributes(:br, [])
  Meta.allow_tag_with_these_attributes(:span, ["class"])
  Meta.allow_tag_with_these_attributes(:blockquote, ["class"])
  Meta.allow_tag_with_these_attributes(:pre, ["class"])
  Meta.allow_tag_with_these_attributes(:code, ["class"])

  Meta.allow_tag_with_these_attributes(:strong, [])
  Meta.allow_tag_with_these_attributes(:em, [])
  Meta.allow_tag_with_these_attributes(:b, [])
  Meta.allow_tag_with_these_attributes(:i, [])
  Meta.allow_tag_with_these_attributes(:u, [])
  Meta.allow_tag_with_these_attributes(:s, [])
  Meta.allow_tag_with_these_attributes(:small, [])
  Meta.allow_tag_with_these_attributes(:sub, [])
  Meta.allow_tag_with_these_attributes(:sup, [])
  Meta.allow_tag_with_these_attributes(:del, [])

  Meta.allow_tag_with_these_attributes(:ul, ["class"])
  Meta.allow_tag_with_these_attributes(:ol, ["class"])
  Meta.allow_tag_with_these_attributes(:li, ["class"])

  Meta.strip_everything_not_covered()
end
