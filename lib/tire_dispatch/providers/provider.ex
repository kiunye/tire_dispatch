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
    field :payout_method, Ecto.Enum, values: [:stripe, :mpesa], default: :stripe
    field :stripe_account_id, :string
    field :stripe_subscription_id, :string
    field :mpesa_phone_number, :string
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
      :payout_method,
      :stripe_account_id,
      :stripe_subscription_id,
      :mpesa_phone_number,
      :latitude,
      :longitude
    ])
    |> validate_required([:user_id, :vehicle_type, :service_radius_km])
    |> validate_inclusion(:vehicle_type, [:compact, :suv, :truck])
    |> validate_inclusion(:payout_method, [:stripe, :mpesa])
    |> validate_number(:service_radius_km, greater_than: 0, less_than_or_equal_to: 100)
    |> validate_number(:rating, greater_than_or_equal_to: 0, less_than_or_equal_to: 5)
    |> validate_location()
    |> validate_payout_method()
    |> unique_constraint(:user_id)
    |> foreign_key_constraint(:user_id)
  end

  defp validate_payout_method(changeset) do
    payout_method = get_field(changeset, :payout_method)

    case payout_method do
      :mpesa ->
        mpesa_phone = get_field(changeset, :mpesa_phone_number)

        if is_nil(mpesa_phone) or mpesa_phone == "" do
          add_error(changeset, :mpesa_phone_number, "is required when payout method is MPESA")
        else
          changeset
        end

      _ ->
        changeset
    end
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
