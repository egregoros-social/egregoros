defmodule PleromaRedux.OAuth.Application do
  use Ecto.Schema

  import Ecto.Changeset

  @required_fields ~w(name redirect_uris client_id client_secret)a
  @optional_fields ~w(website scopes)a

  schema "oauth_applications" do
    field :name, :string
    field :website, :string
    field :redirect_uris, {:array, :string}, default: []
    field :scopes, :string, default: ""
    field :client_id, :string
    field :client_secret, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(application, attrs) do
    application
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, max: 200)
    |> validate_length(:client_id, min: 10, max: 200)
    |> validate_length(:client_secret, min: 10, max: 200)
    |> validate_redirect_uris()
    |> unique_constraint(:client_id)
  end

  defp validate_redirect_uris(changeset) do
    validate_change(changeset, :redirect_uris, fn :redirect_uris, value ->
      cond do
        not is_list(value) ->
          [redirect_uris: "must be a list"]

        Enum.any?(value, &(&1 == nil)) ->
          [redirect_uris: "must not contain null values"]

        Enum.any?(value, &(is_binary(&1) and String.trim(&1) == "")) ->
          [redirect_uris: "must not contain empty values"]

        true ->
          []
      end
    end)
  end
end
