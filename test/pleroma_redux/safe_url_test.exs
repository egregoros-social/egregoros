defmodule PleromaRedux.SafeURLTest do
  use ExUnit.Case, async: true

  import Mox

  alias PleromaRedux.SafeURL

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    stub(PleromaRedux.DNS.Mock, :lookup_ips, fn _host ->
      {:ok, [{1, 1, 1, 1}]}
    end)

    :ok
  end

  test "allows https urls" do
    assert :ok == SafeURL.validate_http_url("https://remote.example/users/alice")
  end

  test "rejects non-http schemes" do
    assert {:error, :unsafe_url} == SafeURL.validate_http_url("file:///etc/passwd")
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

  test "rejects hostnames that resolve to private ips" do
    PleromaRedux.DNS.Mock
    |> expect(:lookup_ips, fn "private.example" ->
      {:ok, [{127, 0, 0, 1}]}
    end)

    assert {:error, :unsafe_url} == SafeURL.validate_http_url("https://private.example/users/alice")
  end
end
