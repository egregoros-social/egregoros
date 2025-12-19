defmodule PleromaRedux.OAuth.Token do
  use Ecto.Schema

  import Ecto.Changeset

  @required_fields ~w(token user_id application_id)a
  @optional_fields ~w(scopes revoked_at)a

  schema "oauth_tokens" do
    field :token, :string
    field :scopes, :string, default: ""
    field :revoked_at, :utc_datetime_usec

    belongs_to :user, PleromaRedux.User
    belongs_to :application, PleromaRedux.OAuth.Application

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:token, min: 10, max: 255)
    |> unique_constraint(:token)
  end
end
