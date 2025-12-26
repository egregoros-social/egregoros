defmodule Egregoros.E2EE.KeyWrapper do
  use Ecto.Schema

  import Ecto.Changeset

  alias Egregoros.User

  @fields ~w(user_id kid type wrapped_private_key params)a
  @required_fields ~w(user_id kid type wrapped_private_key params)a

  schema "e2ee_key_wrappers" do
    belongs_to :user, User

    field :kid, :string
    field :type, :string
    field :wrapped_private_key, :binary
    field :params, :map

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(wrapper, attrs) do
    wrapper
    |> cast(attrs, @fields)
    |> validate_required(@required_fields)
    |> validate_length(:kid, max: 255)
    |> validate_length(:type, max: 64)
    |> unique_constraint([:user_id, :kid, :type])
  end
end
