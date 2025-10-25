defmodule TireDispatch.PricingTest do
  use TireDispatch.DataCase, async: true
  use ExUnitProperties

  alias TireDispatch.Pricing

  describe "get_base_rate/1" do
    test "returns correct base rate for flat_repair" do
      assert {:ok, 3500} = Pricing.get_base_rate(:flat_repair)
    end

    test "returns correct base rate for nail_removal" do
      assert {:ok, 2500} = Pricing.get_base_rate(:nail_removal)
    end

    test "returns correct base rate for air_fill" do
      assert {:ok, 1500} = Pricing.get_base_rate(:air_fill)
    end

    test "returns correct base rate for new_tire" do
      assert {:ok, 8000} = Pricing.get_base_rate(:new_tire)
    end

    test "returns correct base rate for replacement" do
      assert {:ok, 15_000} = Pricing.get_base_rate(:replacement)
    end

    test "returns error for invalid service type" do
      assert {:error, "Invalid service type"} = Pricing.get_base_rate(:invalid_type)
    end
  end

  describe "get_urgency_multiplier/1" do
    test "returns 1.0 for standard urgency" do
      assert Pricing.get_urgency_multiplier(:standard) == 1.0
    end

    test "returns 1.3 for rush urgency" do
      assert Pricing.get_urgency_multiplier(:rush) == 1.3
    end

    test "returns 1.6 for emergency urgency" do
      assert Pricing.get_urgency_multiplier(:emergency) == 1.6
    end

    test "returns 1.0 for invalid urgency" do
      assert Pricing.get_urgency_multiplier(:invalid) == 1.0
    end
  end

  describe "get_vehicle_multiplier/1" do
    test "returns 1.0 for compact vehicle" do
      assert Pricing.get_vehicle_multiplier(:compact) == 1.0
    end

    test "returns 1.1 for suv vehicle" do
      assert Pricing.get_vehicle_multiplier(:suv) == 1.1
    end

    test "returns 1.2 for truck vehicle" do
      assert Pricing.get_vehicle_multiplier(:truck) == 1.2
    end

    test "returns 1.0 for invalid vehicle type" do
      assert Pricing.get_vehicle_multiplier(:invalid) == 1.0
    end
  end

  describe "get_time_multiplier/1" do
    test "returns 1.0 for standard weekday hours (9 AM)" do
      datetime = ~U[2024-01-15 14:00:00Z]
      assert Pricing.get_time_multiplier(datetime) == 1.0
    end

    test "returns 1.15 for evening hours (7 PM)" do
      datetime = ~U[2024-01-15 19:00:00Z]
      assert Pricing.get_time_multiplier(datetime) == 1.15
    end

    test "returns 1.25 for night hours (11 PM)" do
      datetime = ~U[2024-01-15 23:00:00Z]
      assert Pricing.get_time_multiplier(datetime) == 1.25
    end

    test "returns 1.25 for early morning hours (3 AM)" do
      datetime = ~U[2024-01-15 03:00:00Z]
      assert Pricing.get_time_multiplier(datetime) == 1.25
    end

    test "returns 1.25 for Saturday" do
      # January 13, 2024 is a Saturday
      datetime = ~U[2024-01-13 14:00:00Z]
      assert Pricing.get_time_multiplier(datetime) == 1.25
    end

    test "returns 1.25 for Sunday" do
      # January 14, 2024 is a Sunday
      datetime = ~U[2024-01-14 14:00:00Z]
      assert Pricing.get_time_multiplier(datetime) == 1.25
    end
  end

  describe "calculate_quote/4" do
    test "calculates quote with all standard multipliers" do
      driver_location = %{latitude: 41.8781, longitude: -87.6298}

      # Mock the distance calculator to return 1.0
      expect(TireDispatch.Pricing.DistanceCalculatorMock, :calculate_distance_factor, fn _ ->
        {:ok, 1.0}
      end)

      assert {:ok, %{low: low, high: high}} =
               Pricing.calculate_quote(
                 driver_location,
                 :flat_repair,
                 :standard,
                 :compact
               )

      # Base rate: 3500, all multipliers: 1.0
      # Expected: 3500 * 1.0 * 1.0 * 1.0 * 1.0 = 3500
      assert low == 3500
      # High estimate: 3500 * 1.15 = 4025
      assert high == 4025
    end

    test "calculates quote with rush urgency multiplier" do
      driver_location = %{latitude: 41.8781, longitude: -87.6298}

      expect(TireDispatch.Pricing.DistanceCalculatorMock, :calculate_distance_factor, fn _ ->
        {:ok, 1.0}
      end)

      assert {:ok, %{low: low, high: _high}} =
               Pricing.calculate_quote(
                 driver_location,
                 :flat_repair,
                 :rush,
                 :compact
               )

      # Base rate: 3500, urgency: 1.3
      # Expected: 3500 * 1.3 = 4550
      assert low == 4550
    end

    test "calculates quote with emergency urgency multiplier" do
      driver_location = %{latitude: 41.8781, longitude: -87.6298}

      expect(TireDispatch.Pricing.DistanceCalculatorMock, :calculate_distance_factor, fn _ ->
        {:ok, 1.0}
      end)

      assert {:ok, %{low: low, high: _high}} =
               Pricing.calculate_quote(
                 driver_location,
                 :flat_repair,
                 :emergency,
                 :compact
               )

      # Base rate: 3500, urgency: 1.6
      # Expected: 3500 * 1.6 = 5600
      assert low == 5600
    end

    test "calculates quote with SUV vehicle multiplier" do
      driver_location = %{latitude: 41.8781, longitude: -87.6298}

      expect(TireDispatch.Pricing.DistanceCalculatorMock, :calculate_distance_factor, fn _ ->
        {:ok, 1.0}
      end)

      assert {:ok, %{low: low, high: _high}} =
               Pricing.calculate_quote(
                 driver_location,
                 :flat_repair,
                 :standard,
                 :suv
               )

      # Base rate: 3500, vehicle: 1.1
      # Expected: 3500 * 1.1 = 3850
      assert low == 3850
    end

    test "calculates quote with truck vehicle multiplier" do
      driver_location = %{latitude: 41.8781, longitude: -87.6298}

      expect(TireDispatch.Pricing.DistanceCalculatorMock, :calculate_distance_factor, fn _ ->
        {:ok, 1.0}
      end)

      assert {:ok, %{low: low, high: _high}} =
               Pricing.calculate_quote(
                 driver_location,
                 :flat_repair,
                 :standard,
                 :truck
               )

      # Base rate: 3500, vehicle: 1.2
      # Expected: 3500 * 1.2 = 4200
      assert low == 4200
    end

    test "calculates quote with distance factor" do
      driver_location = %{latitude: 41.8781, longitude: -87.6298}

      # Mock distance factor of 1.5
      expect(TireDispatch.Pricing.DistanceCalculatorMock, :calculate_distance_factor, fn _ ->
        {:ok, 1.5}
      end)

      assert {:ok, %{low: low, high: _high}} =
               Pricing.calculate_quote(
                 driver_location,
                 :flat_repair,
                 :standard,
                 :compact
               )

      # Base rate: 3500, distance: 1.5
      # Expected: 3500 * 1.5 = 5250
      assert low == 5250
    end

    test "calculates quote with combined multipliers" do
      driver_location = %{latitude: 41.8781, longitude: -87.6298}

      expect(TireDispatch.Pricing.DistanceCalculatorMock, :calculate_distance_factor, fn _ ->
        {:ok, 1.2}
      end)

      assert {:ok, %{low: low, high: high}} =
               Pricing.calculate_quote(
                 driver_location,
                 :flat_repair,
                 :rush,
                 :suv
               )

      # Base rate: 3500
      # Distance: 1.2, Urgency: 1.3, Vehicle: 1.1
      # Expected: 3500 * 1.2 * 1.3 * 1.1 = 6006
      assert low == 6006
      # High: 6006 * 1.15 = 6907
      assert high == 6907
    end

    test "returns error for invalid service type" do
      driver_location = %{latitude: 41.8781, longitude: -87.6298}

      assert {:error, "Invalid service type"} =
               Pricing.calculate_quote(
                 driver_location,
                 :invalid_type,
                 :standard,
                 :compact
               )
    end
  end

  describe "pricing rules CRUD" do
    test "list_pricing_rules/0 returns all pricing rules" do
      rule1 = insert(:pricing_rule)
      rule2 = insert(:pricing_rule)

      rules = Pricing.list_pricing_rules()

      assert length(rules) >= 2
      rule_ids = Enum.map(rules, & &1.id)
      assert rule1.id in rule_ids
      assert rule2.id in rule_ids
    end

    test "get_pricing_rule!/1 returns rule when it exists" do
      rule = insert(:pricing_rule)
      assert %TireDispatch.Pricing.PricingRule{} = Pricing.get_pricing_rule!(rule.id)
    end

    test "get_pricing_rule!/1 raises when rule doesn't exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Pricing.get_pricing_rule!(Ecto.UUID.generate())
      end
    end

    test "create_pricing_rule/1 creates a new rule" do
      attrs = %{
        rule_type: :base_rate,
        name: "Test Rule",
        value: Decimal.new("100.00"),
        active: true
      }

      assert {:ok, %TireDispatch.Pricing.PricingRule{} = rule} =
               Pricing.create_pricing_rule(attrs)

      assert rule.rule_type == :base_rate
      assert rule.name == "Test Rule"
      assert Decimal.equal?(rule.value, Decimal.new("100.00"))
      assert rule.active == true
    end

    test "update_pricing_rule/2 updates an existing rule" do
      rule = insert(:pricing_rule, value: Decimal.new("100.00"))

      assert {:ok, updated} =
               Pricing.update_pricing_rule(rule, %{value: Decimal.new("150.00")})

      assert Decimal.equal?(updated.value, Decimal.new("150.00"))
    end

    test "delete_pricing_rule/1 deletes a rule" do
      rule = insert(:pricing_rule)

      assert {:ok, _deleted} = Pricing.delete_pricing_rule(rule)
      assert_raise Ecto.NoResultsError, fn -> Pricing.get_pricing_rule!(rule.id) end
    end
  end

  describe "property-based pricing tests" do
    # Generators for pricing inputs
    defp service_type_gen do
      member_of([:flat_repair, :nail_removal, :air_fill, :new_tire, :replacement])
    end

    defp urgency_tier_gen do
      member_of([:standard, :rush, :emergency])
    end

    defp vehicle_type_gen do
      member_of([:compact, :suv, :truck])
    end

    defp location_gen do
      gen all(
            lat <- float(min: -90.0, max: 90.0),
            lng <- float(min: -180.0, max: 180.0)
          ) do
        %{latitude: lat, longitude: lng}
      end
    end

    defp distance_factor_gen do
      float(min: 0.5, max: 3.0)
    end

    property "prices always increase with urgency tier" do
      check all(
              service_type <- service_type_gen(),
              vehicle_type <- vehicle_type_gen(),
              location <- location_gen(),
              distance_factor <- distance_factor_gen()
            ) do
        # Mock distance calculator for all urgency levels
        expect(TireDispatch.Pricing.DistanceCalculatorMock, :calculate_distance_factor, 3, fn _ ->
          {:ok, distance_factor}
        end)

        # Calculate quotes for all urgency tiers
        {:ok, standard_quote} =
          Pricing.calculate_quote(location, service_type, :standard, vehicle_type)

        {:ok, rush_quote} = Pricing.calculate_quote(location, service_type, :rush, vehicle_type)

        {:ok, emergency_quote} =
          Pricing.calculate_quote(location, service_type, :emergency, vehicle_type)

        # Assert that prices increase with urgency
        assert standard_quote.low < rush_quote.low,
               "Standard price (#{standard_quote.low}) should be less than rush price (#{rush_quote.low})"

        assert rush_quote.low < emergency_quote.low,
               "Rush price (#{rush_quote.low}) should be less than emergency price (#{emergency_quote.low})"

        # Also verify high estimates follow the same pattern
        assert standard_quote.high < rush_quote.high
        assert rush_quote.high < emergency_quote.high
      end
    end

    property "prices always increase with vehicle size" do
      check all(
              service_type <- service_type_gen(),
              urgency_tier <- urgency_tier_gen(),
              location <- location_gen(),
              distance_factor <- distance_factor_gen()
            ) do
        # Mock distance calculator for all vehicle types
        expect(TireDispatch.Pricing.DistanceCalculatorMock, :calculate_distance_factor, 3, fn _ ->
          {:ok, distance_factor}
        end)

        # Calculate quotes for all vehicle types
        {:ok, compact_quote} =
          Pricing.calculate_quote(location, service_type, urgency_tier, :compact)

        {:ok, suv_quote} = Pricing.calculate_quote(location, service_type, urgency_tier, :suv)

        {:ok, truck_quote} = Pricing.calculate_quote(location, service_type, urgency_tier, :truck)

        # Assert that prices increase with vehicle size
        assert compact_quote.low < suv_quote.low,
               "Compact price (#{compact_quote.low}) should be less than SUV price (#{suv_quote.low})"

        assert suv_quote.low < truck_quote.low,
               "SUV price (#{suv_quote.low}) should be less than truck price (#{truck_quote.low})"

        # Also verify high estimates follow the same pattern
        assert compact_quote.high < suv_quote.high
        assert suv_quote.high < truck_quote.high
      end
    end

    property "high estimate is always 15% more than low estimate" do
      check all(
              service_type <- service_type_gen(),
              urgency_tier <- urgency_tier_gen(),
              vehicle_type <- vehicle_type_gen(),
              location <- location_gen(),
              distance_factor <- distance_factor_gen()
            ) do
        expect(TireDispatch.Pricing.DistanceCalculatorMock, :calculate_distance_factor, fn _ ->
          {:ok, distance_factor}
        end)

        {:ok, quote} =
          Pricing.calculate_quote(location, service_type, urgency_tier, vehicle_type)

        # High estimate should be low * 1.15 (rounded)
        expected_high = round(quote.low * 1.15)

        assert quote.high == expected_high,
               "High estimate (#{quote.high}) should be 15% more than low estimate (#{quote.low}), expected #{expected_high}"
      end
    end

    property "prices are always positive integers" do
      check all(
              service_type <- service_type_gen(),
              urgency_tier <- urgency_tier_gen(),
              vehicle_type <- vehicle_type_gen(),
              location <- location_gen(),
              distance_factor <- distance_factor_gen()
            ) do
        expect(TireDispatch.Pricing.DistanceCalculatorMock, :calculate_distance_factor, fn _ ->
          {:ok, distance_factor}
        end)

        {:ok, quote} =
          Pricing.calculate_quote(location, service_type, urgency_tier, vehicle_type)

        # Prices should be positive integers
        assert is_integer(quote.low)
        assert is_integer(quote.high)
        assert quote.low > 0
        assert quote.high > 0
      end
    end

    property "prices scale proportionally with distance factor" do
      check all(
              service_type <- service_type_gen(),
              urgency_tier <- urgency_tier_gen(),
              vehicle_type <- vehicle_type_gen(),
              location <- location_gen()
            ) do
        # Test with two different distance factors
        distance_factor_1 = 1.0
        distance_factor_2 = 2.0

        expect(TireDispatch.Pricing.DistanceCalculatorMock, :calculate_distance_factor, 2, fn _ ->
          {:ok, distance_factor_1}
        end)

        {:ok, quote_1} =
          Pricing.calculate_quote(location, service_type, urgency_tier, vehicle_type)

        expect(TireDispatch.Pricing.DistanceCalculatorMock, :calculate_distance_factor, 2, fn _ ->
          {:ok, distance_factor_2}
        end)

        {:ok, quote_2} =
          Pricing.calculate_quote(location, service_type, urgency_tier, vehicle_type)

        # Price with 2x distance should be approximately 2x the price with 1x distance
        # Allow for rounding differences
        ratio = quote_2.low / quote_1.low
        assert_in_delta ratio, 2.0, 0.01,
          "Price ratio (#{ratio}) should be close to distance factor ratio (2.0)"
      end
    end

    property "urgency multipliers are correctly applied" do
      check all(urgency_tier <- urgency_tier_gen()) do
        multiplier = Pricing.get_urgency_multiplier(urgency_tier)

        case urgency_tier do
          :standard -> assert multiplier == 1.0
          :rush -> assert multiplier == 1.3
          :emergency -> assert multiplier == 1.6
        end

        # Multiplier should always be positive
        assert multiplier > 0
      end
    end

    property "vehicle multipliers are correctly applied" do
      check all(vehicle_type <- vehicle_type_gen()) do
        multiplier = Pricing.get_vehicle_multiplier(vehicle_type)

        case vehicle_type do
          :compact -> assert multiplier == 1.0
          :suv -> assert multiplier == 1.1
          :truck -> assert multiplier == 1.2
        end

        # Multiplier should always be positive
        assert multiplier > 0
      end
    end

    property "base rates are consistent and positive" do
      check all(service_type <- service_type_gen()) do
        {:ok, base_rate} = Pricing.get_base_rate(service_type)

        # Base rate should be a positive integer (in cents)
        assert is_integer(base_rate)
        assert base_rate > 0

        # Verify expected base rates
        expected_rate =
          case service_type do
            :flat_repair -> 3500
            :nail_removal -> 2500
            :air_fill -> 1500
            :new_tire -> 8000
            :replacement -> 15_000
          end

        assert base_rate == expected_rate
      end
    end
  end
end
