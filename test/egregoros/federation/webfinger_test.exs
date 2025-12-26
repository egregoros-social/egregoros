defmodule Egregoros.Federation.WebFingerTest do
  use Egregoros.DataCase, async: true

  import Mox

  alias Egregoros.Federation.WebFinger

  test "lookup returns the actor url for a valid acct handle" do
    actor_url = "https://remote.example/users/alice"

    expect(Egregoros.HTTP.Mock, :get, fn url, headers ->
      assert url ==
               "https://remote.example/.well-known/webfinger?resource=acct:alice@remote.example"

      assert {"accept", "application/jrd+json, application/json"} in headers
      assert {"user-agent", "egregoros"} in headers

      {:ok,
       %{
         status: 200,
         body: %{
           "subject" => "acct:alice@remote.example",
           "links" => [
             %{
               "rel" => "self",
               "type" => "application/activity+json",
               "href" => actor_url
             }
           ]
         },
         headers: []
       }}
    end)

    assert {:ok, ^actor_url} = WebFinger.lookup("@alice@remote.example")
  end

  test "lookup returns an error for an invalid handle" do
    stub(Egregoros.HTTP.Mock, :get, fn _url, _headers ->
      flunk("unexpected HTTP fetch for invalid handles")
    end)

    assert {:error, :invalid_handle} = WebFinger.lookup("@alice")
    assert {:error, :invalid_handle} = WebFinger.lookup("")
    assert {:error, :invalid_handle} = WebFinger.lookup("@")
  end

  test "lookup returns :webfinger_failed when the server replies non-2xx" do
    expect(Egregoros.HTTP.Mock, :get, fn _url, _headers ->
      {:ok, %{status: 404, body: %{}, headers: []}}
    end)

    assert {:error, :webfinger_failed} = WebFinger.lookup("@alice@remote.example")
  end

  test "lookup returns :invalid_json when the response body is not JSON" do
    expect(Egregoros.HTTP.Mock, :get, fn _url, _headers ->
      {:ok, %{status: 200, body: "not json", headers: []}}
    end)

    assert {:error, :invalid_json} = WebFinger.lookup("@alice@remote.example")
  end

  test "lookup returns :not_found when the response does not include a self link" do
    expect(Egregoros.HTTP.Mock, :get, fn _url, _headers ->
      {:ok, %{status: 200, body: %{"links" => []}, headers: []}}
    end)

    assert {:error, :not_found} = WebFinger.lookup("@alice@remote.example")
  end

  test "lookup rejects unsafe domains without fetching" do
    stub(Egregoros.HTTP.Mock, :get, fn _url, _headers ->
      flunk("unexpected HTTP fetch for unsafe webfinger domain")
    end)

    assert {:error, :unsafe_url} = WebFinger.lookup("@alice@127.0.0.1")
    assert {:error, :unsafe_url} = WebFinger.lookup("@alice@localhost")
  end
end
