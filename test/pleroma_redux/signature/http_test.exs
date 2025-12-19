defmodule PleromaRedux.Signature.HTTPTest do
  use PleromaRedux.DataCase, async: true

  alias PleromaRedux.Signature.HTTP
  alias PleromaRedux.Users

  test "sign_request generates a verifiable signature" do
    {public_key, private_key} = PleromaRedux.Keys.generate_rsa_keypair()

    {:ok, user} =
      Users.create_user(%{
        nickname: "alice",
        ap_id: "https://remote.example/users/alice",
        inbox: "https://remote.example/users/alice/inbox",
        outbox: "https://remote.example/users/alice/outbox",
        public_key: public_key,
        private_key: private_key,
        local: false
      })

    body = Jason.encode!(%{"id" => "https://remote.example/objects/1", "type" => "Note"})

    {:ok, signed} =
      HTTP.sign_request(user, "post", "https://local.example/users/frank/inbox", body)

    conn =
      Plug.Test.conn(:post, "/users/frank/inbox", body)
      |> Plug.Conn.assign(:raw_body, body)
      |> Plug.Conn.put_req_header("date", signed.date)
      |> Plug.Conn.put_req_header("digest", signed.digest)
      |> Plug.Conn.put_req_header("content-length", signed.content_length)
      |> Plug.Conn.put_req_header("signature", signed.signature)

    conn = %{conn | host: "local.example", scheme: :https, port: 443}

    assert :ok == HTTP.verify_request(conn)
  end
end
