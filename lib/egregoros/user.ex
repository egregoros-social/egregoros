defmodule Egregoros.User do
  use Ecto.Schema

  import Ecto.Changeset

  alias Egregoros.Domain

  @fields ~w(nickname domain ap_id inbox outbox public_key private_key local admin email password_hash name bio avatar_url banner_url emojis)a
  @required_fields ~w(nickname ap_id inbox outbox public_key local)a

  schema "users" do
    field :nickname, :string
    field :domain, :string
    field :ap_id, :string
    field :inbox, :string
    field :outbox, :string
    field :public_key, :string
    field :private_key, :string
    field :local, :boolean, default: true
    field :admin, :boolean, default: false
    field :email, :string
    field :password_hash, :string
    field :name, :string
    field :bio, :string
    field :avatar_url, :string
    field :banner_url, :string
    field :emojis, {:array, :map}, default: []

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, @fields)
    |> validate_required(@required_fields)
    |> maybe_put_domain()
    |> maybe_require_domain()
    |> maybe_require_private_key()
    |> validate_email_format()
    |> unique_constraint(:ap_id)
    |> unique_constraint(:nickname, name: :users_local_nickname_index)
    |> unique_constraint([:nickname, :domain], name: :users_remote_nickname_domain_index)
    |> unique_constraint(:email)
  end

  defp maybe_put_domain(changeset) do
    local = Ecto.Changeset.get_field(changeset, :local)

    cond do
      local ->
        put_change(changeset, :domain, nil)

      is_binary(Ecto.Changeset.get_field(changeset, :domain)) and
          String.trim(Ecto.Changeset.get_field(changeset, :domain)) != "" ->
        changeset

      is_binary(ap_id = Ecto.Changeset.get_field(changeset, :ap_id)) ->
        case URI.parse(ap_id) do
          %URI{} = uri ->
            case Domain.from_uri(uri) do
              domain when is_binary(domain) and domain != "" ->
                put_change(changeset, :domain, domain)

              _ ->
                changeset
            end

          _ ->
            changeset
        end

      true ->
        changeset
    end
  end

  defp maybe_require_domain(changeset) do
    if Ecto.Changeset.get_field(changeset, :local) do
      changeset
    else
      validate_required(changeset, [:domain])
    end
  end

  defp maybe_require_private_key(changeset) do
    if Ecto.Changeset.get_field(changeset, :local) do
      validate_required(changeset, [:private_key])
    else
      changeset
    end
  end

  defp validate_email_format(changeset) do
    validate_format(changeset, :email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
  end
end
