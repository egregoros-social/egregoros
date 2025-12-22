defmodule PleromaReduxWeb.MastodonAPI.PushSubscriptionController do
  use PleromaReduxWeb, :controller

  def show(conn, _params) do
    conn
    |> put_status(:not_found)
    |> json(%{"error" => "push subscriptions are not supported"})
  end

  def create(conn, _params) do
    conn
    |> put_status(:not_found)
    |> json(%{"error" => "push subscriptions are not supported"})
  end

  def update(conn, _params) do
    conn
    |> put_status(:not_found)
    |> json(%{"error" => "push subscriptions are not supported"})
  end

  def delete(conn, _params) do
    conn
    |> put_status(:not_found)
    |> json(%{"error" => "push subscriptions are not supported"})
  end
end

