defmodule PleromaRedux.HTML.Scrubber.Default do
  @moduledoc false

  require FastSanitize.Sanitizer.Meta

  alias FastSanitize.Sanitizer.Meta

  @valid_schemes ["http", "https", "mailto"]
  @valid_image_schemes ["http", "https"]

  Meta.strip_comments()

  Meta.allow_tag_with_uri_attributes(:a, ["href"], @valid_schemes)
  Meta.allow_tag_with_these_attributes(:a, ["class", "rel", "title", "target"])

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
