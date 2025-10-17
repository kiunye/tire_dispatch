defmodule TireDispatch.Pricing do
  @moduledoc """
  The Pricing context handles dynamic quote calculations and pricing rule management.
  """

  alias TireDispatch.Pricing.PricingRule
  alias TireDispatch.Repo

  # Base rates in cents for each service type
  @base_rates %{
    flat_repair: 3500,
    nail_removal: 2500,
    air_fill: 1500,
    new_tire: 8000,
    replacement: 15_000
  }

  @doc """
  Calculates a dynamic price quote based on service type, urgency, vehicle type, and time.

  Returns a map with `:low` and `:high` estimates in cents.

  ## Parameters

    * `driver_location` - Map with `:latitude` and `:longitude` keys
    * `service_type` - Atom representing the service type
    * `urgency_tier` - Atom: `:standard`, `:rush`, or `:emergency`
    * `vehicle_type` - Atom: `:compact`, `:suv`, or `:truck`

  ## Examples

      iex> calculate_quote(%{latitude: 40.7128, longitude: -74.0060}, :flat_repair, :standard, :compact)
      {:ok, %{low: 3500, high: 4025}}

  """
  def calculate_quote(driver_location, service_type, urgency_tier, vehicle_type) do
    with {:ok, base_rate} <- get_base_rate(service_type),
         {:ok, distance_factor} <- calculate_distance_factor(driver_location),
         urgency_multiplier <- get_urgency_multiplier(urgency_tier),
         vehicle_multiplier <- get_vehicle_multiplier(vehicle_type),
         time_multiplier <- get_time_multiplier(DateTime.utc_now()) do
      # Calculate final price: base_rate × distance_factor × urgency × vehicle × time
      low_estimate =
        (base_rate * distance_factor * urgency_multiplier * vehicle_multiplier * time_multiplier)
        |> round()

      high_estimate = (low_estimate * 1.15) |> round()

      {:ok, %{low: low_estimate, high: high_estimate}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns the base rate in cents for a given service type.

  ## Examples

      iex> get_base_rate(:flat_repair)
      {:ok, 3500}

  """
  def get_base_rate(service_type) when is_atom(service_type) do
    case Map.get(@base_rates, service_type) do
      nil -> {:error, "Invalid service type"}
      rate -> {:ok, rate}
    end
  end

  @doc """
  Calculates the distance factor based on driver location.

  Uses Google Distance Matrix API to calculate accurate driving distance
  to the nearest provider. Falls back to PostGIS distance calculation if API fails.

  ## Examples

      iex> calculate_distance_factor(%{latitude: 40.7128, longitude: -74.0060})
      {:ok, 1.0}

  """
  def calculate_distance_factor(driver_location) do
    alias TireDispatch.Pricing.DistanceCalculator

    DistanceCalculator.calculate_distance_factor(driver_location)
  end

  @doc """
  Returns the urgency multiplier for a given urgency tier.

  ## Examples

      iex> get_urgency_multiplier(:standard)
      1.0

      iex> get_urgency_multiplier(:rush)
      1.3

      iex> get_urgency_multiplier(:emergency)
      1.6

  """
  def get_urgency_multiplier(:standard), do: 1.0
  def get_urgency_multiplier(:rush), do: 1.3
  def get_urgency_multiplier(:emergency), do: 1.6
  def get_urgency_multiplier(_), do: 1.0

  @doc """
  Returns the vehicle multiplier for a given vehicle type.

  ## Examples

      iex> get_vehicle_multiplier(:compact)
      1.0

      iex> get_vehicle_multiplier(:suv)
      1.1

      iex> get_vehicle_multiplier(:truck)
      1.2

  """
  def get_vehicle_multiplier(:compact), do: 1.0
  def get_vehicle_multiplier(:suv), do: 1.1
  def get_vehicle_multiplier(:truck), do: 1.2
  def get_vehicle_multiplier(_), do: 1.0

  @doc """
  Returns the time multiplier based on the current datetime.

  Time multipliers:
  - Standard hours (6 AM - 6 PM weekdays): 1.0x
  - Evenings (6 PM - 10 PM weekdays): 1.15x
  - Nights/Weekends (10 PM - 6 AM or weekends): 1.25x
  - Holidays: 1.5x (not yet implemented)

  ## Examples

      iex> get_time_multiplier(~U[2024-01-15 14:00:00Z])
      1.0

  """
  def get_time_multiplier(%DateTime{} = datetime) do
    hour = datetime.hour
    day_of_week = Date.day_of_week(datetime)

    cond do
      # Weekend (Saturday = 6, Sunday = 7)
      day_of_week in [6, 7] ->
        1.25

      # Night hours (10 PM - 6 AM)
      hour >= 22 or hour < 6 ->
        1.25

      # Evening hours (6 PM - 10 PM)
      hour >= 18 and hour < 22 ->
        1.15

      # Standard hours (6 AM - 6 PM weekdays)
      true ->
        1.0
    end
  end

  # Pricing Rules CRUD Operations

  @doc """
  Returns the list of pricing rules.

  ## Examples

      iex> list_pricing_rules()
      [%PricingRule{}, ...]

  """
  def list_pricing_rules do
    Repo.all(PricingRule)
  end

  @doc """
  Gets a single pricing rule.

  Raises `Ecto.NoResultsError` if the Pricing rule does not exist.

  ## Examples

      iex> get_pricing_rule!(123)
      %PricingRule{}

      iex> get_pricing_rule!(456)
      ** (Ecto.NoResultsError)

  """
  def get_pricing_rule!(id), do: Repo.get!(PricingRule, id)

  @doc """
  Creates a pricing rule.

  ## Examples

      iex> create_pricing_rule(%{field: value})
      {:ok, %PricingRule{}}

      iex> create_pricing_rule(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_pricing_rule(attrs \\ %{}) do
    result =
      %PricingRule{}
      |> PricingRule.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, rule} ->
        # Add to cache
        TireDispatch.Pricing.PricingCache.set_rule(rule.id, rule)
        {:ok, rule}

      error ->
        error
    end
  end

  @doc """
  Updates a pricing rule.

  ## Examples

      iex> update_pricing_rule(pricing_rule, %{field: new_value})
      {:ok, %PricingRule{}}

      iex> update_pricing_rule(pricing_rule, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_pricing_rule(%PricingRule{} = pricing_rule, attrs) do
    result =
      pricing_rule
      |> PricingRule.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, rule} ->
        # Update cache
        TireDispatch.Pricing.PricingCache.set_rule(rule.id, rule)
        {:ok, rule}

      error ->
        error
    end
  end

  @doc """
  Deletes a pricing rule.

  ## Examples

      iex> delete_pricing_rule(pricing_rule)
      {:ok, %PricingRule{}}

      iex> delete_pricing_rule(pricing_rule)
      {:error, %Ecto.Changeset{}}

  """
  def delete_pricing_rule(%PricingRule{} = pricing_rule) do
    result = Repo.delete(pricing_rule)

    case result do
      {:ok, rule} ->
        # Remove from cache
        TireDispatch.Pricing.PricingCache.delete_rule(rule.id)
        {:ok, rule}

      error ->
        error
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking pricing rule changes.

  ## Examples

      iex> change_pricing_rule(pricing_rule)
      %Ecto.Changeset{data: %PricingRule{}}

  """
  def change_pricing_rule(%PricingRule{} = pricing_rule, attrs \\ %{}) do
    PricingRule.changeset(pricing_rule, attrs)
  end

  @doc """
  Refreshes the pricing cache by reloading all pricing rules from the database.

  This is useful after bulk updates or when cache consistency needs to be ensured.

  ## Examples

      iex> refresh_pricing_cache()
      :ok

  """
  def refresh_pricing_cache do
    TireDispatch.Pricing.PricingCache.refresh_all()
  end
end
