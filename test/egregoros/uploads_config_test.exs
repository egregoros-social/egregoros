defmodule Egregoros.UploadsConfigTest do
  use ExUnit.Case, async: true

  test "uses an isolated uploads dir in tests to avoid touching priv/static/uploads" do
    uploads_dir = Application.fetch_env!(:egregoros, :uploads_dir)

    default_uploads_dir =
      :egregoros
      |> :code.priv_dir()
      |> to_string()
      |> Path.join(["static", "uploads"])

    refute Path.expand(uploads_dir) == Path.expand(default_uploads_dir)
  end
end
