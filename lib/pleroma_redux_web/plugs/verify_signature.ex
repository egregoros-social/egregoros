defmodule PleromaReduxWeb.Plugs.VerifySignature do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case PleromaRedux.Signature.verify_request(conn) do
      {:ok, signer_ap_id} ->
        conn
        |> assign(:signature_actor_ap_id, signer_ap_id)
        |> verify_activity_actor(signer_ap_id)

      {:error, _reason} ->
        conn
        |> send_resp(401, "Unauthorized")
        |> halt()
    end
  end

  defp verify_activity_actor(conn, signer_ap_id) when is_binary(signer_ap_id) do
    case activity_actor_id(conn.body_params) do
      ^signer_ap_id ->
        conn

      nil ->
        conn
        |> send_resp(401, "Unauthorized")
        |> halt()

      _ ->
        conn
        |> send_resp(401, "Unauthorized")
        |> halt()
    end
  end

  defp verify_activity_actor(conn, _signer_ap_id), do: conn

  defp activity_actor_id(%{"actor" => %{"id" => id}}) when is_binary(id), do: id
  defp activity_actor_id(%{"actor" => %{id: id}}) when is_binary(id), do: id
  defp activity_actor_id(%{"actor" => id}) when is_binary(id), do: id
  defp activity_actor_id(%{"attributedTo" => %{"id" => id}}) when is_binary(id), do: id
  defp activity_actor_id(%{"attributedTo" => %{id: id}}) when is_binary(id), do: id
  defp activity_actor_id(%{"attributedTo" => id}) when is_binary(id), do: id
  defp activity_actor_id(_), do: nil
end
