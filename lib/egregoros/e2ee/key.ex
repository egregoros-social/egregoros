defmodule Egregoros.E2EE.Key do
  use Ecto.Schema

  import Ecto.Changeset

  alias Egregoros.User

  @fields ~w(user_id kid public_key_jwk fingerprint active)a
  @required_fields ~w(user_id kid public_key_jwk fingerprint active)a

  schema "e2ee_keys" do
    belongs_to :user, User

    field :kid, :string
    field :public_key_jwk, :map
    field :fingerprint, :string
    field :active, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(key, attrs) do
    key
    |> cast(attrs, @fields)
    |> validate_required(@required_fields)
    |> validate_length(:kid, max: 255)
    |> validate_public_key_jwk()
    |> unique_constraint([:user_id, :kid])
    |> unique_constraint(:user_id, name: :e2ee_keys_one_active_per_user)
  end

  defp validate_public_key_jwk(changeset) do
    case get_field(changeset, :public_key_jwk) do
      %{"kty" => kty, "crv" => crv, "x" => x, "y" => y}
      when is_binary(kty) and is_binary(crv) and is_binary(x) and is_binary(y) ->
        changeset

      %{} ->
        add_error(changeset, :public_key_jwk, "must be a valid JWK with kty/crv/x/y")

      _ ->
        add_error(changeset, :public_key_jwk, "must be a valid JWK map")
    end
  end
end
