defmodule TireDispatch.Pricing.DistanceCalculator do
  @moduledoc """
  Calculates distance factors using Google Distance Matrix API with PostGIS fallback.
  """

  require Logger

  @doc """
  Calculates the distance factor based on driver location and nearby providers.

  Uses Google Distance Matrix API to get accurate driving distance.
  Falls back to PostGIS distance calculation if API fails.

  Returns a distance factor multiplier:
  - 1.0 for distances under 5 km
  - 1.1 for distances 5-10 km
  - 1.2 for distances 10-20 km
  - 1.3 for distances over 20 km

  ## Parameters

    * `driver_location` - Map with `:latitude` and `:longitude` keys
    * `opts` - Optional keyword list with:
      * `:provider_location` - Specific provider location to calculate distance to
      * `:radius_km` - Search radius for finding nearby providers (default: 20)

  ## Examples

      iex> calculate_distance_factor(%{latitude: 40.7128, longitude: -74.0060})
      {:ok, 1.0}

  """
  def calculate_distance_factor(driver_location, opts \\ []) do
    provider_location = Keyword.get(opts, :provider_location)
    radius_km = Keyword.get(opts, :radius_km, 20)

    # If specific provider location is given, calculate distance to that provider
    # Otherwise, find nearest provider and calculate distance
    if provider_location do
      calculate_distance_to_provider(driver_location, provider_location)
    else
      calculate_distance_to_nearest_provider(driver_location, radius_km)
    end
  end

  @doc """
  Calculates distance factor to a specific provider location.
  """
  def calculate_distance_to_provider(driver_location, provider_location) do
    case fetch_google_distance(driver_location, provider_location) do
      {:ok, distance_km} ->
        {:ok, distance_to_factor(distance_km)}

      {:error, reason} ->
        Logger.warning(
          "Google Distance Matrix API failed: #{inspect(reason)}, falling back to PostGIS"
        )

        fallback_to_postgis_distance(driver_location, provider_location)
    end
  end

  @doc """
  Calculates distance factor to the nearest available provider.
  """
  def calculate_distance_to_nearest_provider(driver_location, radius_km) do
    alias TireDispatch.Providers

    # Find nearest provider within radius
    case Providers.list_providers_within_radius(
           driver_location.latitude,
           driver_location.longitude,
           radius_km
         ) do
      [] ->
        # No providers found, use maximum distance factor
        Logger.info("No providers found within #{radius_km}km, using max distance factor")
        {:ok, 1.3}

      [nearest_provider | _] ->
        provider_location = %{
          latitude: nearest_provider.latitude,
          longitude: nearest_provider.longitude
        }

        calculate_distance_to_provider(driver_location, provider_location)
    end
  end

  # Private Functions

  defp fetch_google_distance(origin, destination) do
    api_key = Application.get_env(:tire_dispatch, :google_maps_api_key)

    if is_nil(api_key) or api_key == "" do
      {:error, :api_key_not_configured}
    else
      url = build_distance_matrix_url(origin, destination, api_key)

      case Req.get(url) do
        {:ok, %{status: 200, body: body}} ->
          parse_distance_response(body)

        {:ok, %{status: status}} ->
          {:error, "API returned status #{status}"}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp build_distance_matrix_url(origin, destination, api_key) do
    origin_str = "#{origin.latitude},#{origin.longitude}"
    destination_str = "#{destination.latitude},#{destination.longitude}"

    "https://maps.googleapis.com/maps/api/distancematrix/json" <>
      "?origins=#{URI.encode(origin_str)}" <>
      "&destinations=#{URI.encode(destination_str)}" <>
      "&key=#{api_key}"
  end

  defp parse_distance_response(body) do
    case body do
      %{"status" => "OK", "rows" => [%{"elements" => [element | _]} | _]} ->
        case element do
          %{"status" => "OK", "distance" => %{"value" => distance_meters}} ->
            distance_km = distance_meters / 1000
            {:ok, distance_km}

          %{"status" => status} ->
            {:error, "Element status: #{status}"}

          _ ->
            {:error, :invalid_response_format}
        end

      %{"status" => status} ->
        {:error, "API status: #{status}"}

      _ ->
        {:error, :invalid_response_format}
    end
  end

  defp fallback_to_postgis_distance(driver_location, provider_location) do
    # Calculate straight-line distance using PostGIS
    distance_km =
      calculate_haversine_distance(
        driver_location.latitude,
        driver_location.longitude,
        provider_location.latitude,
        provider_location.longitude
      )

    {:ok, distance_to_factor(distance_km)}
  end

  defp calculate_haversine_distance(lat1, lon1, lat2, lon2) do
    # Haversine formula for calculating distance between two points on Earth
    # Returns distance in kilometers

    # Convert degrees to radians
    lat1_rad = lat1 * :math.pi() / 180
    lat2_rad = lat2 * :math.pi() / 180
    delta_lat = (lat2 - lat1) * :math.pi() / 180
    delta_lon = (lon2 - lon1) * :math.pi() / 180

    # Haversine formula
    a =
      :math.sin(delta_lat / 2) * :math.sin(delta_lat / 2) +
        :math.cos(lat1_rad) * :math.cos(lat2_rad) *
          :math.sin(delta_lon / 2) * :math.sin(delta_lon / 2)

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))

    # Earth's radius in kilometers
    radius = 6371

    radius * c
  end

  defp distance_to_factor(distance_km) do
    cond do
      distance_km < 5 -> 1.0
      distance_km < 10 -> 1.1
      distance_km < 20 -> 1.2
      true -> 1.3
    end
  end
end
