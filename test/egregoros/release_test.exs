defmodule Egregoros.ReleaseTest do
  use ExUnit.Case, async: false

  alias Egregoros.Release

  test "healthcheck returns :ok when the endpoint responds 200" do
    response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    {port, server_ref} = start_http_server(response)

    original_port = System.get_env("PORT")
    System.put_env("PORT", Integer.to_string(port))

    on_exit(fn ->
      restore_env("PORT", original_port)
    end)

    assert :ok = Release.healthcheck()
    assert_receive {:http_request, ^server_ref, request}, 1_000
    assert request =~ "GET /health HTTP/1.1"
  end

  test "healthcheck returns {:error, :bad_status} for non-200 responses" do
    response = "HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n"
    {port, _server_ref} = start_http_server(response)

    assert {:error, :bad_status} =
             Release.healthcheck(
               host: {127, 0, 0, 1},
               port: port,
               path: "/health",
               timeout: 1_000
             )
  end

  test "healthcheck returns an error tuple when the TCP connection fails" do
    assert {:error, _reason} = Release.healthcheck(host: {127, 0, 0, 1}, port: 0, timeout: 100)
  end

  test "healthcheck treats a blank PORT env var as 4000" do
    original_port = System.get_env("PORT")
    System.put_env("PORT", "")

    on_exit(fn ->
      restore_env("PORT", original_port)
    end)

    assert {:error, _reason} = Release.healthcheck(timeout: 100)
  end

  defp start_http_server(response) when is_binary(response) do
    {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen_socket)
    ref = make_ref()
    parent = self()

    start_supervised!({Task, fn -> serve_once(listen_socket, response, parent, ref) end})

    {port, ref}
  end

  defp serve_once(listen_socket, response, parent, ref)
       when is_port(listen_socket) and is_binary(response) do
    {:ok, socket} = :gen_tcp.accept(listen_socket)
    {:ok, request} = :gen_tcp.recv(socket, 0, 1_000)
    send(parent, {:http_request, ref, request})
    :ok = :gen_tcp.send(socket, response)
    _ = :gen_tcp.close(socket)
    _ = :gen_tcp.close(listen_socket)
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
