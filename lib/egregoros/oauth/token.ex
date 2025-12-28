defmodule Egregoros.OAuth.Token do
  use Ecto.Schema

  import Ecto.Changeset

  @required_fields ~w(token refresh_token application_id)a
  @optional_fields ~w(user_id scopes expires_at refresh_expires_at revoked_at)a

  schema "oauth_tokens" do
    field :token, :string
    field :refresh_token, :string
    field :scopes, :string, default: ""
    field :expires_at, :utc_datetime_usec
    field :refresh_expires_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec

    belongs_to :user, Egregoros.User
    belongs_to :application, Egregoros.OAuth.Application

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:token, min: 10, max: 255)
    |> validate_length(:refresh_token, min: 10, max: 255)
    |> unique_constraint(:token)
    |> unique_constraint(:refresh_token)
  end
end
