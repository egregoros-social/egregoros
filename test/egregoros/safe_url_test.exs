defmodule Egregoros.SafeURLTest do
  use ExUnit.Case, async: true

  import Mox

  alias Egregoros.SafeURL

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    stub(Egregoros.DNS.Mock, :lookup_ips, fn _host ->
      {:ok, [{1, 1, 1, 1}]}
    end)

    :ok
  end

  test "allows https urls" do
    assert :ok == SafeURL.validate_http_url("https://remote.example/users/alice")
  end

  test "allows http urls" do
    assert :ok == SafeURL.validate_http_url("http://remote.example/users/alice")
  end

  test "rejects non-http schemes" do
    assert {:error, :unsafe_url} == SafeURL.validate_http_url("file:///etc/passwd")
  end

  test "rejects urls without a host" do
    assert {:error, :unsafe_url} == SafeURL.validate_http_url("https:///users/alice")
    assert {:error, :unsafe_url} == SafeURL.validate_http_url("https://")
  end

  test "rejects non-binary urls" do
    assert {:error, :unsafe_url} == SafeURL.validate_http_url(nil)
    assert {:error, :unsafe_url} == SafeURL.validate_http_url(123)
  end

  test "rejects localhost" do
    assert {:error, :unsafe_url} == SafeURL.validate_http_url("http://localhost/users/alice")
  end

  test "rejects loopback ip literals" do
    assert {:error, :unsafe_url} == SafeURL.validate_http_url("http://127.0.0.1/users/alice")
    assert {:error, :unsafe_url} == SafeURL.validate_http_url("http://[::1]/users/alice")
  end

  test "rejects private ip literals" do
    assert {:error, :unsafe_url} == SafeURL.validate_http_url("http://10.0.0.1/users/alice")
    assert {:error, :unsafe_url} == SafeURL.validate_http_url("http://192.168.0.1/users/alice")
  end

  test "rejects invalid ip literals" do
    assert {:error, :unsafe_url} ==
             SafeURL.validate_http_url("http://999.999.999.999/users/alice")
  end

  test "rejects private ipv6 literals" do
    assert {:error, :unsafe_url} == SafeURL.validate_http_url("http://[fc00::1]/users/alice")
    assert {:error, :unsafe_url} == SafeURL.validate_http_url("http://[fe80::1]/users/alice")
  end

  test "allows public ipv6 literals" do
    assert :ok == SafeURL.validate_http_url("http://[2001:4860:4860::8888]/users/alice")
  end

  test "rejects hostnames that resolve to private ips" do
    Egregoros.DNS.Mock
    |> expect(:lookup_ips, fn "private.example" ->
      {:ok, [{127, 0, 0, 1}]}
    end)

    assert {:error, :unsafe_url} ==
             SafeURL.validate_http_url("https://private.example/users/alice")
  end

  test "rejects hostnames with no public IPs" do
    Egregoros.DNS.Mock
    |> expect(:lookup_ips, fn "empty.example" -> {:ok, []} end)

    assert {:error, :unsafe_url} ==
             SafeURL.validate_http_url("https://empty.example/users/alice")

    Egregoros.DNS.Mock
    |> expect(:lookup_ips, fn "missing.example" -> {:error, :nxdomain} end)

    assert {:error, :unsafe_url} ==
             SafeURL.validate_http_url("https://missing.example/users/alice")
  end

  test "validate_http_url_no_dns allows hostnames without DNS lookups" do
    Egregoros.DNS.Mock
    |> expect(:lookup_ips, 0, fn _host -> {:ok, [{127, 0, 0, 1}]} end)

    assert :ok == SafeURL.validate_http_url_no_dns("https://remote.example/users/alice")
  end

  test "validate_http_url_no_dns rejects localhost and private ip literals" do
    assert {:error, :unsafe_url} == SafeURL.validate_http_url_no_dns("http://localhost/users/alice")
    assert {:error, :unsafe_url} == SafeURL.validate_http_url_no_dns("http://127.0.0.1/users/alice")
    assert {:error, :unsafe_url} == SafeURL.validate_http_url_no_dns("http://10.0.0.1/users/alice")
    assert {:error, :unsafe_url} == SafeURL.validate_http_url_no_dns("http://[::1]/users/alice")
  end
end
