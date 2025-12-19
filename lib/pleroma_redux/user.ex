defmodule PleromaRedux.User do
  use Ecto.Schema

  import Ecto.Changeset

  @required_fields ~w(nickname ap_id inbox outbox public_key private_key local)a

  schema "users" do
    field :nickname, :string
    field :ap_id, :string
    field :inbox, :string
    field :outbox, :string
    field :public_key, :string
    field :private_key, :string
    field :local, :boolean, default: true

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:ap_id)
    |> unique_constraint(:nickname)
  end
end
