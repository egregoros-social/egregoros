defmodule EgregorosWeb.AdminController do
  use EgregorosWeb, :controller

  alias Egregoros.Activities.Undo
  alias Egregoros.BadgeDefinition
  alias Egregoros.Badges
  alias Egregoros.Federation.InstanceActor
  alias Egregoros.InstanceSettings
  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Relays
  alias Egregoros.Repo
  alias Egregoros.User
  alias EgregorosWeb.Param

  def index(conn, _params) do
    form = Phoenix.Component.to_form(%{"ap_id" => ""}, as: :relay)
    registrations_open? = InstanceSettings.registrations_open?()

    badge_form =
      Phoenix.Component.to_form(
        %{"badge_type" => "", "recipient_ap_id" => "", "expires_on" => ""},
        as: :badge_issue
      )

    registrations_form =
      Phoenix.Component.to_form(
        %{"open" => registrations_open?},
        as: :registrations
      )

    badge_definitions = Badges.list_definitions(include_disabled?: true)
    badge_options = Enum.map(badge_definitions, &{&1.name, &1.badge_type})

    badge_definition_forms =
      Enum.map(badge_definitions, fn badge ->
        {badge,
         Phoenix.Component.to_form(BadgeDefinition.changeset(badge, %{}), as: :badge_definition)}
      end)

    render(conn, :index,
      relays: Relays.list_relays(),
      form: form,
      registrations_open?: registrations_open?,
      registrations_form: registrations_form,
      badge_form: badge_form,
      badge_options: badge_options,
      badge_definition_forms: badge_definition_forms,
      badge_offers: Badges.list_offers(limit: 50),
      notifications_count: notifications_count(conn.assigns.current_user)
    )
  end

  def update_registrations(conn, %{"registrations" => %{} = params}) do
    open? = Param.truthy?(Map.get(params, "open"))

    case InstanceSettings.set_registrations_open(open?) do
      {:ok, _settings} ->
        conn
        |> put_flash(:info, "Registration settings updated.")
        |> redirect(to: ~p"/admin")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Could not update registration settings.")
        |> redirect(to: ~p"/admin")
    end
  end

  def update_registrations(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> text("Unprocessable Entity")
  end

  def create_relay(conn, %{"relay" => %{} = params}) do
    ap_id = params |> Map.get("ap_id", "") |> to_string() |> String.trim()

    case Relays.subscribe(ap_id) do
      {:ok, _relay} ->
        conn
        |> put_flash(:info, "Relay subscribed.")
        |> redirect(to: ~p"/admin")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Could not subscribe to relay.")
        |> redirect(to: ~p"/admin")
    end
  end

  def create_relay(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> text("Unprocessable Entity")
  end

  def issue_badge(conn, %{"badge_issue" => %{} = params}) do
    badge_type = params |> Map.get("badge_type", "") |> to_string() |> String.trim()
    recipient_ap_id = params |> Map.get("recipient_ap_id", "") |> to_string() |> String.trim()
    expires_on = params |> Map.get("expires_on", "") |> to_string() |> String.trim()

    opts = badge_issue_opts(expires_on)

    case Badges.issue_badge(badge_type, recipient_ap_id, opts) do
      {:ok, _result} ->
        conn
        |> put_flash(:info, "Badge issued.")
        |> redirect(to: ~p"/admin")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Could not issue badge.")
        |> redirect(to: ~p"/admin")
    end
  end

  def issue_badge(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> text("Unprocessable Entity")
  end

  def update_badge_definition(conn, %{"id" => id, "badge_definition" => %{} = params}) do
    id = id |> to_string() |> String.trim()

    with true <- flake_id?(id),
         %BadgeDefinition{} = badge <- Repo.get(BadgeDefinition, id),
         {:ok, _badge} <- Badges.update_definition(badge, params) do
      conn
      |> put_flash(:info, "Badge updated.")
      |> redirect(to: ~p"/admin")
    else
      _ ->
        conn
        |> put_flash(:error, "Could not update badge.")
        |> redirect(to: ~p"/admin")
    end
  end

  def update_badge_definition(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> text("Unprocessable Entity")
  end

  def delete_relay(conn, %{"id" => id}) do
    id = id |> to_string() |> String.trim()

    with {:ok, _relay} <- Relays.unsubscribe(id) do
      conn
      |> put_flash(:info, "Relay unsubscribed.")
      |> redirect(to: ~p"/admin")
    else
      _ ->
        conn
        |> put_flash(:error, "Could not unsubscribe from relay.")
        |> redirect(to: ~p"/admin")
    end
  end

  def rescind_offer(conn, %{"id" => id}) do
    with %Object{type: "Offer"} = offer <- fetch_offer(id),
         {:ok, %User{} = issuer} <- InstanceActor.get_actor(),
         {:ok, _undo_object} <- Pipeline.ingest(Undo.build(issuer, offer), local: true) do
      conn
      |> put_flash(:info, "Offer rescinded.")
      |> redirect(to: ~p"/admin")
    else
      _ ->
        conn
        |> put_flash(:error, "Could not rescind offer.")
        |> redirect(to: ~p"/admin")
    end
  end

  def rescind_offer(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> text("Unprocessable Entity")
  end

  defp notifications_count(%User{} = user) do
    Egregoros.Notifications.list_for_user(user, limit: 20, include_offers?: true)
    |> length()
  end

  defp notifications_count(_), do: 0

  defp fetch_offer(id) when is_binary(id) do
    id = String.trim(id)

    cond do
      id == "" ->
        nil

      true ->
        Objects.get(id) || Objects.get_by_ap_id(id)
    end
  end

  defp fetch_offer(_id), do: nil

  defp badge_issue_opts(""), do: []

  defp badge_issue_opts(expires_on) when is_binary(expires_on) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Date.from_iso8601(expires_on) do
      {:ok, date} ->
        case DateTime.new(date, ~T[23:59:59], "Etc/UTC") do
          {:ok, valid_until} ->
            [valid_from: now, valid_until: valid_until]

          _ ->
            []
        end

      _ ->
        []
    end
  end

  defp badge_issue_opts(_expires_on), do: []

  defp flake_id?(id) when is_binary(id) do
    id = String.trim(id)

    byte_size(id) == 18 and FlakeId.flake_id?(id)
  end

  defp flake_id?(_id), do: false
end
