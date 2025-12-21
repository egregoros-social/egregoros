defmodule PleromaRedux.Signature.HTTPActorFetchTest do
  use PleromaRedux.DataCase, async: true

  import Mox

  alias PleromaRedux.Keys
  alias PleromaRedux.Users

  test "verify_request fetches unknown actor public key" do
    actor_url = "https://remote.example/users/alice"
    {public_key, private_key_pem} = Keys.generate_rsa_keypair()

    PleromaRedux.HTTP.Mock
    |> expect(:get, fn url, _headers ->
      assert url == actor_url

      {:ok,
       %{
         status: 200,
         body: %{
           "id" => actor_url,
           "type" => "Person",
           "preferredUsername" => "alice",
           "inbox" => actor_url <> "/inbox",
           "outbox" => actor_url <> "/outbox",
           "publicKey" => %{
             "id" => actor_url <> "#main-key",
             "owner" => actor_url,
             "publicKeyPem" => public_key
           }
         },
         headers: []
       }}
    end)

    date = :httpd_util.rfc1123_date() |> List.to_string()

    signature_string =
      [
        "(request-target): post /users/frank/inbox",
        "date: " <> date
      ]
      |> Enum.join("\n")

    [entry] = :public_key.pem_decode(private_key_pem)
    private_key = :public_key.pem_entry_decode(entry)
    signature = :public_key.sign(signature_string, :sha256, private_key) |> Base.encode64()

    header =
      "Signature " <>
        "keyId=\"#{actor_url}#main-key\"," <>
        "algorithm=\"rsa-sha256\"," <>
        "headers=\"(request-target) date\"," <>
        "signature=\"#{signature}\""

    conn =
      Plug.Test.conn(:post, "/users/frank/inbox", "")
      |> Plug.Conn.put_req_header("date", date)
      |> Plug.Conn.put_req_header("authorization", header)

    assert {:ok, ^actor_url} = PleromaRedux.Signature.verify_request(conn)
    assert Users.get_by_ap_id(actor_url)
  end

  test "verify_request rejects unsafe actor urls" do
    actor_url = "http://127.0.0.1/users/alice"

    stub(PleromaRedux.HTTP.Mock, :get, fn _url, _headers ->
      flunk("unexpected HTTP fetch for unsafe actor url")
    end)

    date = :httpd_util.rfc1123_date() |> List.to_string()

    header =
      "Signature " <>
        "keyId=\"#{actor_url}#main-key\"," <>
        "algorithm=\"rsa-sha256\"," <>
        "headers=\"(request-target) date\"," <>
        "signature=\"AA==\""

    conn =
      Plug.Test.conn(:post, "/users/frank/inbox", "")
      |> Plug.Conn.put_req_header("date", date)
      |> Plug.Conn.put_req_header("authorization", header)

    assert {:error, :unsafe_url} = PleromaRedux.Signature.verify_request(conn)
  end

  test "verify_request rejects invalid stored public keys without crashing" do
    actor_url = "https://remote.example/users/alice"

    {:ok, _user} =
      Users.create_user(%{
        nickname: "alice",
        ap_id: actor_url,
        inbox: actor_url <> "/inbox",
        outbox: actor_url <> "/outbox",
        public_key: "not-a-pem",
        private_key: nil,
        local: false
      })

    date = :httpd_util.rfc1123_date() |> List.to_string()

    header =
      "Signature " <>
        "keyId=\"#{actor_url}#main-key\"," <>
        "algorithm=\"rsa-sha256\"," <>
        "headers=\"(request-target) date\"," <>
        "signature=\"AA==\""

    conn =
      Plug.Test.conn(:post, "/users/frank/inbox", "")
      |> Plug.Conn.put_req_header("date", date)
      |> Plug.Conn.put_req_header("authorization", header)

    assert {:error, :unknown_key} = PleromaRedux.Signature.verify_request(conn)
  end
end
