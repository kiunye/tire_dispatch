defmodule TireDispatch.Pricing.PricingRule do
  @moduledoc """
  PricingRule schema for admin-configurable pricing rules.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "pricing_rules" do
    field :rule_type, Ecto.Enum,
      values: [
        :distance_multiplier,
        :urgency_surcharge,
        :vehicle_modifier,
        :time_adjustment,
        :add_on
      ]

    field :name, :string
    field :value, :decimal
    field :conditions, :map, default: %{}
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating or updating a pricing rule.
  """
  def changeset(pricing_rule, attrs) do
    pricing_rule
    |> cast(attrs, [:rule_type, :name, :value, :conditions, :active])
    |> validate_required([:rule_type, :name, :value])
    |> validate_inclusion(:rule_type, [
      :distance_multiplier,
      :urgency_surcharge,
      :vehicle_modifier,
      :time_adjustment,
      :add_on
    ])
    |> validate_number(:value, greater_than_or_equal_to: 0)
    |> validate_length(:name, min: 1, max: 255)
  end
end
