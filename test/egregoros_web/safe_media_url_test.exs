defmodule EgregorosWeb.SafeMediaURLTest do
  use ExUnit.Case, async: true

  alias EgregorosWeb.Endpoint
  alias EgregorosWeb.SafeMediaURL

  test "allows same-origin absolute urls" do
    url = Endpoint.url() <> "/uploads/media/1.png"
    assert SafeMediaURL.safe(url) == url
  end

  test "allows relative urls by expanding to same-origin absolute url" do
    assert SafeMediaURL.safe("/uploads/media/1.png") == Endpoint.url() <> "/uploads/media/1.png"
  end

  test "rejects scheme-relative urls" do
    assert SafeMediaURL.safe("//evil.example/x.png") == nil
  end

  test "rejects non-http schemes" do
    assert SafeMediaURL.safe("javascript:alert(1)") == nil
    assert SafeMediaURL.safe("data:image/png;base64,AAAA") == nil
  end

  test "rejects private ip urls" do
    assert SafeMediaURL.safe("http://127.0.0.1/evil.png") == nil
    assert SafeMediaURL.safe("http://10.0.0.1/evil.png") == nil
  end

  test "allows external http(s) urls with safe hostnames" do
    url = "https://example.com/media/1.png"
    assert SafeMediaURL.safe(url) == url
  end
end

