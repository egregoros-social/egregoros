defmodule Egregoros.OAuth.Token do
  use Ecto.Schema

  import Ecto.Changeset

  @required_fields ~w(token_digest refresh_token_digest application_id)a
  @optional_fields ~w(user_id scopes expires_at refresh_expires_at revoked_at)a

  schema "oauth_tokens" do
    field :token_digest, :string
    field :refresh_token_digest, :string
    field :token, :string, virtual: true
    field :refresh_token, :string, virtual: true
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
    |> validate_length(:token_digest, is: 64)
    |> validate_length(:refresh_token_digest, is: 64)
    |> unique_constraint(:token_digest)
    |> unique_constraint(:refresh_token_digest)
  end
end
