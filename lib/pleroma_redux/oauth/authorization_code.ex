defmodule PleromaRedux.OAuth.AuthorizationCode do
  use Ecto.Schema

  import Ecto.Changeset

  @required_fields ~w(code redirect_uri expires_at user_id application_id)a
  @optional_fields ~w(scopes)a

  schema "oauth_authorization_codes" do
    field :code, :string
    field :redirect_uri, :string
    field :scopes, :string, default: ""
    field :expires_at, :utc_datetime_usec

    belongs_to :user, PleromaRedux.User
    belongs_to :application, PleromaRedux.OAuth.Application

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(code, attrs) do
    code
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:code, min: 10, max: 255)
    |> validate_length(:redirect_uri, min: 1, max: 2000)
    |> unique_constraint(:code)
  end
end
