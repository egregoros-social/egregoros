defmodule PleromaReduxWeb.Plugs.VerifySignatureTest do
  use PleromaRedux.DataCase, async: true

  import Plug.Test

  alias PleromaRedux.Signature.HTTP, as: HTTPSignature
  alias PleromaRedux.Users
  alias PleromaReduxWeb.Plugs.VerifySignature

  test "passes through when signature is valid and activity actor matches" do
    {:ok, user} = Users.create_local_user("alice")

    body = Jason.encode!(%{"id" => "https://remote.example/activities/1", "type" => "Follow"})

    {:ok, signed} =
      HTTPSignature.sign_request(user, "post", "https://local.example/users/frank/inbox", body)

    conn =
      conn(:post, "/users/frank/inbox", body)
      |> Plug.Conn.assign(:raw_body, body)
      |> Plug.Conn.put_req_header("date", signed.date)
      |> Plug.Conn.put_req_header("digest", signed.digest)
      |> Plug.Conn.put_req_header("content-length", signed.content_length)
      |> Plug.Conn.put_req_header("signature", signed.signature)

    conn = %{conn | host: "local.example", scheme: :https, port: 443}
    conn = %{conn | body_params: %{"actor" => user.ap_id}}

    conn = VerifySignature.call(conn, [])

    refute conn.halted
    assert conn.assigns.signature_actor_ap_id == user.ap_id
  end

  test "rejects requests with missing signatures" do
    conn =
      conn(:post, "/users/frank/inbox", "{}")
      |> Plug.Conn.assign(:raw_body, "{}")
      |> VerifySignature.call([])

    assert conn.halted
    assert conn.status == 401
  end

  test "rejects requests where the activity actor does not match the signer" do
    {:ok, user} = Users.create_local_user("alice")

    body = Jason.encode!(%{"id" => "https://remote.example/activities/1", "type" => "Follow"})

    {:ok, signed} =
      HTTPSignature.sign_request(user, "post", "https://local.example/users/frank/inbox", body)

    conn =
      conn(:post, "/users/frank/inbox", body)
      |> Plug.Conn.assign(:raw_body, body)
      |> Plug.Conn.put_req_header("date", signed.date)
      |> Plug.Conn.put_req_header("digest", signed.digest)
      |> Plug.Conn.put_req_header("content-length", signed.content_length)
      |> Plug.Conn.put_req_header("signature", signed.signature)

    conn = %{conn | host: "local.example", scheme: :https, port: 443}
    conn = %{conn | body_params: %{"actor" => "https://remote.example/users/mallory"}}

    conn = VerifySignature.call(conn, [])

    assert conn.halted
    assert conn.status == 401
  end

  test "allows requests when the activity actor is missing from body params" do
    {:ok, user} = Users.create_local_user("alice")

    body = Jason.encode!(%{"id" => "https://remote.example/activities/1", "type" => "Follow"})

    {:ok, signed} =
      HTTPSignature.sign_request(user, "post", "https://local.example/users/frank/inbox", body)

    conn =
      conn(:post, "/users/frank/inbox", body)
      |> Plug.Conn.assign(:raw_body, body)
      |> Plug.Conn.put_req_header("date", signed.date)
      |> Plug.Conn.put_req_header("digest", signed.digest)
      |> Plug.Conn.put_req_header("content-length", signed.content_length)
      |> Plug.Conn.put_req_header("signature", signed.signature)

    conn = %{conn | host: "local.example", scheme: :https, port: 443}
    conn = %{conn | body_params: %{}}

    conn = VerifySignature.call(conn, [])

    assert conn.halted
    assert conn.status == 401
  end

  test "passes through when actor is missing but attributedTo matches the signer" do
    {:ok, user} = Users.create_local_user("alice")

    body =
      Jason.encode!(%{
        "id" => "https://remote.example/objects/1",
        "type" => "Note",
        "attributedTo" => user.ap_id
      })

    {:ok, signed} =
      HTTPSignature.sign_request(user, "post", "https://local.example/users/frank/inbox", body)

    conn =
      conn(:post, "/users/frank/inbox", body)
      |> Plug.Conn.assign(:raw_body, body)
      |> Plug.Conn.put_req_header("date", signed.date)
      |> Plug.Conn.put_req_header("digest", signed.digest)
      |> Plug.Conn.put_req_header("content-length", signed.content_length)
      |> Plug.Conn.put_req_header("signature", signed.signature)

    conn = %{conn | host: "local.example", scheme: :https, port: 443}
    conn = %{conn | body_params: %{"attributedTo" => user.ap_id}}

    conn = VerifySignature.call(conn, [])

    refute conn.halted
    assert conn.assigns.signature_actor_ap_id == user.ap_id
  end

  test "rejects requests where attributedTo does not match the signer" do
    {:ok, user} = Users.create_local_user("alice")

    body =
      Jason.encode!(%{
        "id" => "https://remote.example/objects/1",
        "type" => "Note",
        "attributedTo" => "https://remote.example/users/mallory"
      })

    {:ok, signed} =
      HTTPSignature.sign_request(user, "post", "https://local.example/users/frank/inbox", body)

    conn =
      conn(:post, "/users/frank/inbox", body)
      |> Plug.Conn.assign(:raw_body, body)
      |> Plug.Conn.put_req_header("date", signed.date)
      |> Plug.Conn.put_req_header("digest", signed.digest)
      |> Plug.Conn.put_req_header("content-length", signed.content_length)
      |> Plug.Conn.put_req_header("signature", signed.signature)

    conn = %{conn | host: "local.example", scheme: :https, port: 443}
    conn = %{conn | body_params: %{"attributedTo" => "https://remote.example/users/mallory"}}

    conn = VerifySignature.call(conn, [])

    assert conn.halted
    assert conn.status == 401
  end
end
