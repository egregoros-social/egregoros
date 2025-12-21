defmodule PleromaReduxWeb.BodyReaderTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias PleromaReduxWeb.BodyReader

  test "captures raw_body for small request bodies" do
    conn = conn(:post, "/inbox", "hello")

    assert {:ok, "hello", conn} = BodyReader.read_body(conn, [])
    assert conn.assigns.raw_body == "hello"
  end

  test "accumulates raw_body when reading in chunks" do
    conn = conn(:post, "/inbox", "abcdef")

    assert {:more, "abc", conn} = BodyReader.read_body(conn, length: 3, read_length: 3)
    assert conn.assigns.raw_body == "abc"

    assert {:ok, "def", conn} = BodyReader.read_body(conn, length: 3, read_length: 3)
    assert conn.assigns.raw_body == "abcdef"
  end
end

