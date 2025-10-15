defmodule TireDispatch.Providers.Provider do
  @moduledoc """
  Provider schema for tire service providers.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "providers" do
    belongs_to :user, TireDispatch.Users.User

    field :service_radius_km, :integer, default: 10
    field :vehicle_type, Ecto.Enum, values: [:compact, :suv, :truck]
    field :rating, :decimal, default: Decimal.new("0.0")
    field :is_active, :boolean, default: true
    field :is_verified, :boolean, default: false
    field :is_premium, :boolean, default: false
    field :stripe_account_id, :string
    field :latitude, :float
    field :longitude, :float

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating or updating a provider.
  """
  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [
      :user_id,
      :service_radius_km,
      :vehicle_type,
      :rating,
      :is_active,
      :is_verified,
      :is_premium,
      :stripe_account_id,
      :latitude,
      :longitude
    ])
    |> validate_required([:user_id, :vehicle_type, :service_radius_km])
    |> validate_inclusion(:vehicle_type, [:compact, :suv, :truck])
    |> validate_number(:service_radius_km, greater_than: 0, less_than_or_equal_to: 100)
    |> validate_number(:rating, greater_than_or_equal_to: 0, less_than_or_equal_to: 5)
    |> validate_location()
    |> unique_constraint(:user_id)
    |> foreign_key_constraint(:user_id)
  end

  defp validate_location(changeset) do
    latitude = get_field(changeset, :latitude)
    longitude = get_field(changeset, :longitude)

    cond do
      is_nil(latitude) and is_nil(longitude) ->
        changeset

      is_nil(latitude) or is_nil(longitude) ->
        changeset
        |> add_error(:latitude, "both latitude and longitude must be provided")
        |> add_error(:longitude, "both latitude and longitude must be provided")

      true ->
        changeset
        |> validate_number(:latitude, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
        |> validate_number(:longitude, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    end
  end
end
