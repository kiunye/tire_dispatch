defmodule TireDispatch.ProvidersTest do
  use TireDispatch.DataCase, async: true

  alias TireDispatch.Providers
  alias TireDispatch.Providers.Provider

  describe "create_provider/2" do
    test "creates a provider with valid attributes" do
      user = insert(:provider_user)

      attrs = %{
        vehicle_type: :suv,
        service_radius_km: 15,
        latitude: 41.8781,
        longitude: -87.6298
      }

      assert {:ok, %Provider{} = provider} = Providers.create_provider(user.id, attrs)
      assert provider.user_id == user.id
      assert provider.vehicle_type == :suv
      assert provider.service_radius_km == 15
      assert provider.latitude == 41.8781
      assert provider.longitude == -87.6298
      assert provider.is_active == true
      assert provider.is_verified == false
    end

    test "returns error with invalid vehicle_type" do
      user = insert(:provider_user)

      attrs = %{
        vehicle_type: :invalid_type,
        service_radius_km: 15,
        latitude: 41.8781,
        longitude: -87.6298
      }

      assert {:error, %Ecto.Changeset{} = changeset} = Providers.create_provider(user.id, attrs)
      assert "is invalid" in errors_on(changeset).vehicle_type
    end
  end

  describe "get_provider!/1 and get_provider_by_user_id/1" do
    test "get_provider!/1 returns provider when it exists" do
      provider = insert(:provider)
      assert %Provider{} = found = Providers.get_provider!(provider.id)
      assert found.id == provider.id
    end

    test "get_provider!/1 raises when provider doesn't exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Providers.get_provider!(999_999)
      end
    end

    test "get_provider_by_user_id/1 returns provider when it exists" do
      provider = insert(:provider)
      assert {:ok, %Provider{} = found} = Providers.get_provider_by_user_id(provider.user_id)
      assert found.id == provider.id
    end

    test "get_provider_by_user_id/1 returns error when not found" do
      assert {:error, :not_found} = Providers.get_provider_by_user_id(999_999)
    end
  end

  describe "update_provider/2" do
    test "updates provider with valid attributes" do
      provider = insert(:provider, service_radius_km: 15)

      assert {:ok, %Provider{} = updated} =
               Providers.update_provider(provider, %{service_radius_km: 20})

      assert updated.service_radius_km == 20
    end

    test "returns error with invalid attributes" do
      provider = insert(:provider)

      assert {:error, %Ecto.Changeset{}} =
               Providers.update_provider(provider, %{service_radius_km: -5})
    end
  end

  describe "verify_provider/1" do
    test "marks provider as verified" do
      provider = insert(:unverified_provider)

      assert {:ok, %Provider{} = verified} = Providers.verify_provider(provider.id)
      assert verified.is_verified == true
    end
  end

  describe "update_rating/2" do
    test "updates provider rating" do
      provider = insert(:provider, rating: Decimal.new("4.0"))
      new_rating = Decimal.new("4.5")

      assert {:ok, %Provider{} = updated} = Providers.update_rating(provider.id, new_rating)
      assert Decimal.equal?(updated.rating, new_rating)
    end
  end

  describe "list_providers/1" do
    test "returns all providers" do
      provider1 = insert(:provider)
      provider2 = insert(:provider)

      providers = Providers.list_providers()

      assert length(providers) == 2
      provider_ids = Enum.map(providers, & &1.id)
      assert provider1.id in provider_ids
      assert provider2.id in provider_ids
    end

    test "preloads associations when specified" do
      insert(:provider)

      providers = Providers.list_providers(preload: [:user])

      assert length(providers) == 1
      assert Ecto.assoc_loaded?(hd(providers).user)
    end
  end

  describe "list_active_providers/0" do
    test "returns only active providers" do
      active_provider = insert(:provider, is_active: true)
      insert(:provider, is_active: false)

      providers = Providers.list_active_providers()

      assert length(providers) == 1
      assert hd(providers).id == active_provider.id
    end
  end

  describe "list_verified_providers/0" do
    test "returns only verified providers" do
      verified_provider = insert(:provider, is_verified: true)
      insert(:unverified_provider)

      providers = Providers.list_verified_providers()

      assert length(providers) == 1
      assert hd(providers).id == verified_provider.id
    end
  end

  describe "list_providers_within_radius/3" do
    test "returns providers within specified radius" do
      # Create provider at specific location
      provider =
        insert(:provider,
          latitude: 41.8781,
          longitude: -87.6298,
          is_active: true,
          is_verified: true
        )

      # Search near the provider location (within 1km)
      providers = Providers.list_providers_within_radius(41.8781, -87.6298, 1)

      assert length(providers) == 1
      assert hd(providers).id == provider.id
    end

    test "excludes providers outside specified radius" do
      # Create provider at Chicago location
      insert(:provider,
        latitude: 41.8781,
        longitude: -87.6298,
        is_active: true,
        is_verified: true
      )

      # Search in New York (far away)
      providers = Providers.list_providers_within_radius(40.7128, -74.0060, 1)

      assert providers == []
    end

    test "excludes inactive providers" do
      insert(:provider,
        latitude: 41.8781,
        longitude: -87.6298,
        is_active: false,
        is_verified: true
      )

      providers = Providers.list_providers_within_radius(41.8781, -87.6298, 1)

      assert providers == []
    end

    test "excludes unverified providers" do
      insert(:unverified_provider,
        latitude: 41.8781,
        longitude: -87.6298,
        is_active: true
      )

      providers = Providers.list_providers_within_radius(41.8781, -87.6298, 1)

      assert providers == []
    end

    test "orders providers by distance ascending" do
      # Create providers at different distances
      near_provider =
        insert(:provider,
          latitude: 41.8781,
          longitude: -87.6298,
          is_active: true,
          is_verified: true
        )

      far_provider =
        insert(:provider,
          latitude: 41.9000,
          longitude: -87.7000,
          is_active: true,
          is_verified: true
        )

      # Search from near location
      providers = Providers.list_providers_within_radius(41.8781, -87.6298, 50)

      assert length(providers) == 2
      assert hd(providers).id == near_provider.id
      assert List.last(providers).id == far_provider.id
    end
  end

  describe "calculate_provider_distance/3" do
    test "calculates distance between provider and point" do
      provider = insert(:provider, latitude: 41.8781, longitude: -87.6298)

      distance = Providers.calculate_provider_distance(provider, 41.8900, -87.6400)

      assert is_float(distance)
      assert distance > 0
      # Distance should be roughly 1.5km
      assert distance > 1000 and distance < 2000
    end

    test "returns nil when provider has no latitude" do
      provider = insert(:provider, latitude: nil, longitude: -87.6298)

      assert is_nil(Providers.calculate_provider_distance(provider, 41.8900, -87.6400))
    end

    test "returns nil when provider has no longitude" do
      provider = insert(:provider, latitude: 41.8781, longitude: nil)

      assert is_nil(Providers.calculate_provider_distance(provider, 41.8900, -87.6400))
    end
  end

  describe "list_providers_covering_location/2" do
    test "returns providers whose service radius covers the location" do
      # Provider with 15km radius
      provider =
        insert(:provider,
          latitude: 41.8781,
          longitude: -87.6298,
          service_radius_km: 15,
          is_active: true,
          is_verified: true
        )

      # Search within 10km of provider (should be covered)
      providers = Providers.list_providers_covering_location(41.8900, -87.6400)

      assert length(providers) >= 1
      assert Enum.any?(providers, fn p -> p.id == provider.id end)
    end

    test "excludes providers whose service radius doesn't cover location" do
      # Provider with small 1km radius
      insert(:provider,
        latitude: 41.8781,
        longitude: -87.6298,
        service_radius_km: 1,
        is_active: true,
        is_verified: true
      )

      # Search 10km away (outside radius)
      providers = Providers.list_providers_covering_location(41.9500, -87.7500)

      assert providers == []
    end
  end

  describe "find_nearest_provider/2" do
    test "returns nearest provider to location" do
      near_provider =
        insert(:provider,
          latitude: 41.8781,
          longitude: -87.6298,
          is_active: true,
          is_verified: true
        )

      insert(:provider,
        latitude: 41.9500,
        longitude: -87.7500,
        is_active: true,
        is_verified: true
      )

      assert {:ok, %Provider{} = found} = Providers.find_nearest_provider(41.8781, -87.6298)
      assert found.id == near_provider.id
    end

    test "returns error when no providers available" do
      assert {:error, :not_found} = Providers.find_nearest_provider(41.8781, -87.6298)
    end

    test "excludes inactive providers" do
      insert(:provider,
        latitude: 41.8781,
        longitude: -87.6298,
        is_active: false,
        is_verified: true
      )

      assert {:error, :not_found} = Providers.find_nearest_provider(41.8781, -87.6298)
    end
  end

  describe "premium?/1" do
    test "returns true for premium provider" do
      provider = insert(:premium_provider)

      assert Providers.premium?(provider.id) == true
    end

    test "returns false for standard provider" do
      provider = insert(:provider, is_premium: false)

      assert Providers.premium?(provider.id) == false
    end
  end
end
