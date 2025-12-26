defmodule Egregoros.Federation.SignedFetchTest do
  use Egregoros.DataCase, async: true

  import Mox

  alias Egregoros.Federation.SignedFetch
  alias EgregorosWeb.Endpoint

  setup :verify_on_exit!

  test "signed get includes signature and authorization headers" do
    url = "https://remote.example/objects/1"

    expect(Egregoros.HTTP.Mock, :get, fn fetched_url, headers ->
      assert fetched_url == url
      assert {"accept", "application/activity+json, application/ld+json"} in headers
      assert {"user-agent", "egregoros"} in headers
      assert {"host", "remote.example"} in headers

      assert {"date", _date} = List.keyfind(headers, "date", 0)
      assert {"signature", signature} = List.keyfind(headers, "signature", 0)
      refute String.starts_with?(signature, "Signature ")

      key_id = Endpoint.url() <> "/users/internal.fetch#main-key"
      assert String.contains?(signature, "keyId=\"#{key_id}\"")

      assert {"authorization", "Signature " <> ^signature} =
               List.keyfind(headers, "authorization", 0)

      {:ok, %{status: 200, body: %{"ok" => true}, headers: []}}
    end)

    assert {:ok, %{status: 200, body: %{"ok" => true}}} = SignedFetch.get(url)
  end
end
