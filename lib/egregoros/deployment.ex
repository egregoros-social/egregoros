defmodule Egregoros.Deployment do
  @moduledoc """
  Deployment helpers that run on boot.
  """

  require Logger

  alias Egregoros.BadgeDefinition
  alias Egregoros.Repo
  alias Egregoros.User
  alias Egregoros.Users

  @spec bootstrap() :: :ok
  def bootstrap do
    nickname = Egregoros.Config.get(:bootstrap_admin_nickname)

    case bootstrap_admin(nickname) do
      :ok ->
        :ok

      {:error, :user_not_found} ->
        Logger.warning("bootstrap admin user not found: #{inspect(nickname)}")
        :ok

      {:error, reason} ->
        Logger.error("bootstrap admin failed: #{inspect(reason)}")
        :ok
    end

    _ = maybe_seed_fedbox_admin()
    _ = maybe_seed_fedbox_badge_definition()

    :ok
  end

  @spec bootstrap_admin(String.t() | nil) :: :ok | {:error, term()}
  def bootstrap_admin(nil), do: :ok

  def bootstrap_admin(nickname) when is_binary(nickname) do
    nickname = String.trim(nickname)

    if nickname == "" do
      :ok
    else
      case Users.get_by_nickname(nickname) do
        nil ->
          {:error, :user_not_found}

        user ->
          case Users.set_admin(user, true) do
            {:ok, _user} -> :ok
            {:error, reason} -> {:error, reason}
          end
      end
    end
  end

  def bootstrap_admin(_), do: {:error, :invalid_nickname}

  defp maybe_seed_fedbox_admin do
    nickname = env_trimmed("EGREGOROS_FEDBOX_ADMIN_NICKNAME")
    password = env_value("EGREGOROS_FEDBOX_ADMIN_PASSWORD")
    email = env_trimmed("EGREGOROS_FEDBOX_ADMIN_EMAIL")

    cond do
      nickname == "" or password == "" ->
        :ok

      true ->
        user =
          case Users.get_by_nickname(nickname) do
            %User{} = user -> user
            _ -> create_fedbox_admin(nickname, password, email)
          end

        case user do
          %User{} = user ->
            case Users.set_admin(user, true) do
              {:ok, _user} ->
                :ok

              {:error, reason} ->
                Logger.warning("fedbox admin promotion failed: #{inspect(reason)}")
                :ok
            end

          _ ->
            Logger.warning("fedbox admin user missing: #{inspect(nickname)}")
            :ok
        end
    end
  end

  defp create_fedbox_admin(nickname, password, email)
       when is_binary(nickname) and is_binary(password) do
    email =
      if email == "" do
        "#{nickname}@fedbox.local"
      else
        email
      end

    case Users.register_local_user(%{nickname: nickname, password: password, email: email}) do
      {:ok, %User{} = user} ->
        user

      {:error, reason} ->
        Logger.warning("fedbox admin seed failed: #{inspect(reason)}")
        nil
    end
  end

  defp create_fedbox_admin(_nickname, _password, _email), do: nil

  defp maybe_seed_fedbox_badge_definition do
    badge_type = env_trimmed("EGREGOROS_FEDBOX_BADGE_TYPE")

    if badge_type == "" do
      :ok
    else
      case Repo.get_by(BadgeDefinition, badge_type: badge_type) do
        %BadgeDefinition{} ->
          :ok

        nil ->
          attrs = %{
            badge_type: badge_type,
            name: env_default("EGREGOROS_FEDBOX_BADGE_NAME", "Fedbox Badge"),
            description: env_default("EGREGOROS_FEDBOX_BADGE_DESCRIPTION", "Fedbox test badge"),
            narrative: env_default("EGREGOROS_FEDBOX_BADGE_NARRATIVE", "Issued in fedbox"),
            disabled: false
          }

          %BadgeDefinition{}
          |> BadgeDefinition.changeset(attrs)
          |> Repo.insert()
          |> case do
            {:ok, _badge} ->
              :ok

            {:error, reason} ->
              Logger.warning("fedbox badge seed failed: #{inspect(reason)}")
              :ok
          end
      end
    end
  end

  defp env_value(key) when is_binary(key) do
    case System.get_env(key) do
      value when is_binary(value) -> value
      _ -> ""
    end
  end

  defp env_trimmed(key) when is_binary(key) do
    key |> env_value() |> String.trim()
  end

  defp env_default(key, default) when is_binary(key) and is_binary(default) do
    value = env_trimmed(key)
    if value == "", do: default, else: value
  end
end
