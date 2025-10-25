defmodule TireDispatch.Providers do
  @moduledoc """
  The Providers context handles tire service provider management.

  This context manages provider registration, verification, ratings,
  geographic queries, and Stripe Connect integration.
  """

  import Ecto.Query, warn: false

  alias TireDispatch.Providers.Provider
  alias TireDispatch.Repo

  require Logger

  @doc """
  Creates a new provider profile for a user.

  ## Arguments

    * `user_id` - UUID of the user becoming a provider
    * `attrs` - Map with vehicle_type, service_radius_km, latitude, longitude

  ## Returns

    * `{:ok, provider}` on success
    * `{:error, changeset}` if validation fails

  ## Examples

      iex> create_provider(user_id, %{
        vehicle_type: :suv,
        service_radius_km: 15,
        latitude: 41.8781,
        longitude: -87.6298
      })
      {:ok, %Provider{}}

  """
  def create_provider(user_id, attrs) do
    attrs = Map.put(attrs, :user_id, user_id)

    %Provider{}
    |> Provider.changeset(attrs)
    |> Repo.insert()
    |> tap(&log_provider_created/1)
  end

  @doc """
  Gets a single provider by ID.

  Raises `Ecto.NoResultsError` if the Provider does not exist.

  ## Examples

      iex> get_provider!(123)
      %Provider{}

      iex> get_provider!(456)
      ** (Ecto.NoResultsError)

  """
  def get_provider!(id) do
    Repo.get!(Provider, id)
  end

  @doc """
  Gets a single provider by ID with preloaded user association.

  ## Examples

      iex> get_provider_with_user!(123)
      %Provider{user: %User{}}

  """
  def get_provider_with_user!(id) do
    Provider
    |> Repo.get!(id)
    |> Repo.preload(:user)
  end

  @doc """
  Gets a provider by user_id.

  ## Arguments

    * `user_id` - UUID of the user

  ## Returns

    * `{:ok, provider}` if found
    * `{:error, :not_found}` if not found

  ## Examples

      iex> get_provider_by_user_id(user_id)
      {:ok, %Provider{}}

      iex> get_provider_by_user_id(invalid_user_id)
      {:error, :not_found}

  """
  def get_provider_by_user_id(user_id) do
    case Repo.get_by(Provider, user_id: user_id) do
      nil -> {:error, :not_found}
      provider -> {:ok, provider}
    end
  end

  @doc """
  Updates a provider's profile.

  ## Arguments

    * `provider` - The provider struct to update
    * `attrs` - Map of attributes to update

  ## Returns

    * `{:ok, provider}` on success
    * `{:error, changeset}` if validation fails

  ## Examples

      iex> update_provider(provider, %{service_radius_km: 20})
      {:ok, %Provider{service_radius_km: 20}}

  """
  def update_provider(%Provider{} = provider, attrs) do
    provider
    |> Provider.changeset(attrs)
    |> Repo.update()
    |> tap(&log_provider_updated/1)
  end

  @doc """
  Verifies a provider, allowing them to accept jobs.

  Only verified providers can accept jobs on the platform.

  ## Arguments

    * `provider_id` - UUID of the provider to verify

  ## Returns

    * `{:ok, provider}` on success
    * `{:error, changeset}` if update fails

  ## Examples

      iex> verify_provider(provider_id)
      {:ok, %Provider{is_verified: true}}

  """
  def verify_provider(provider_id) do
    provider = get_provider!(provider_id)

    provider
    |> Provider.changeset(%{is_verified: true})
    |> Repo.update()
    |> tap(&log_provider_verified/1)
  end

  @doc """
  Updates a provider's rating.

  Ratings are on a scale of 0.0 to 5.0.

  ## Arguments

    * `provider_id` - UUID of the provider
    * `new_rating` - Decimal rating value (0.0 to 5.0)

  ## Returns

    * `{:ok, provider}` on success
    * `{:error, changeset}` if validation fails

  ## Examples

      iex> update_rating(provider_id, Decimal.new("4.5"))
      {:ok, %Provider{rating: #Decimal<4.5>}}

  """
  def update_rating(provider_id, new_rating) do
    provider = get_provider!(provider_id)

    provider
    |> Provider.changeset(%{rating: new_rating})
    |> Repo.update()
    |> tap(&log_rating_updated/1)
  end

  @doc """
  Lists all providers.

  ## Options

    * `:preload` - List of associations to preload (default: [])

  ## Examples

      iex> list_providers()
      [%Provider{}, ...]

      iex> list_providers(preload: [:user])
      [%Provider{user: %User{}}, ...]

  """
  def list_providers(opts \\ []) do
    preload = Keyword.get(opts, :preload, [])

    Provider
    |> order_by([p], desc: p.inserted_at)
    |> Repo.all()
    |> Repo.preload(preload)
  end

  @doc """
  Lists active providers.

  ## Examples

      iex> list_active_providers()
      [%Provider{is_active: true}, ...]

  """
  def list_active_providers do
    from(p in Provider,
      where: p.is_active == true,
      order_by: [desc: p.rating]
    )
    |> Repo.all()
  end

  @doc """
  Lists verified providers.

  ## Examples

      iex> list_verified_providers()
      [%Provider{is_verified: true}, ...]

  """
  def list_verified_providers do
    from(p in Provider,
      where: p.is_verified == true,
      order_by: [desc: p.rating]
    )
    |> Repo.all()
  end

  # Private logging functions

  defp log_provider_created({:ok, provider}) do
    Logger.info("Provider created", %{
      provider_id: provider.id,
      user_id: provider.user_id,
      vehicle_type: provider.vehicle_type
    })

    {:ok, provider}
  end

  defp log_provider_created(error), do: error

  defp log_provider_updated({:ok, provider}) do
    Logger.info("Provider updated", %{
      provider_id: provider.id,
      user_id: provider.user_id
    })

    {:ok, provider}
  end

  defp log_provider_updated(error), do: error

  defp log_provider_verified({:ok, provider}) do
    Logger.info("Provider verified", %{
      provider_id: provider.id,
      user_id: provider.user_id
    })

    {:ok, provider}
  end

  defp log_provider_verified(error), do: error

  defp log_rating_updated({:ok, provider}) do
    Logger.info("Provider rating updated", %{
      provider_id: provider.id,
      new_rating: provider.rating
    })

    {:ok, provider}
  end

  defp log_rating_updated(error), do: error

  # Geographic query functions using PostGIS

  @doc """
  Lists providers within a specified radius of a location.

  Only returns active and verified providers, ordered by distance (closest first).

  ## Arguments

    * `lat` - Latitude of the center point
    * `long` - Longitude of the center point
    * `radius_km` - Radius in kilometers

  ## Returns

    * List of providers within the specified radius, ordered by distance

  ## Examples

      iex> list_providers_within_radius(41.8781, -87.6298, 10)
      [%Provider{}, ...]

  """
  def list_providers_within_radius(lat, long, radius_km) do
    # Convert radius to meters for PostGIS calculation
    radius_meters = radius_km * 1000

    # Create a point from the provided coordinates
    # Note: PostGIS uses (longitude, latitude) order
    point_wkt = "POINT(#{long} #{lat})"

    from(p in Provider,
      where: p.is_active == true,
      where: p.is_verified == true,
      where: not is_nil(p.latitude),
      where: not is_nil(p.longitude),
      where:
        fragment(
          "ST_DistanceSphere(ST_MakePoint(?, ?), ST_GeomFromText(?, 4326)) <= ?",
          p.longitude,
          p.latitude,
          ^point_wkt,
          ^radius_meters
        ),
      order_by:
        fragment(
          "ST_DistanceSphere(ST_MakePoint(?, ?), ST_GeomFromText(?, 4326)) ASC",
          p.longitude,
          p.latitude,
          ^point_wkt
        ),
      preload: [:user]
    )
    |> Repo.all()
  end

  @doc """
  Calculates the distance in meters between a provider's location and a given point.

  ## Arguments

    * `provider` - Provider struct with latitude and longitude
    * `lat` - Latitude of the comparison point
    * `long` - Longitude of the comparison point

  ## Returns

    * Distance in meters as a float, or nil if provider location is not set

  ## Examples

      iex> calculate_provider_distance(provider, 41.8781, -87.6298)
      1234.5

  """
  def calculate_provider_distance(%Provider{latitude: nil}, _lat, _long), do: nil
  def calculate_provider_distance(%Provider{longitude: nil}, _lat, _long), do: nil

  def calculate_provider_distance(%Provider{latitude: p_lat, longitude: p_long}, lat, long) do
    point_wkt = "POINT(#{long} #{lat})"

    query =
      from(p in Provider,
        select:
          fragment(
            "ST_Distance_Sphere(ST_MakePoint(?, ?), ST_GeomFromText(?, 4326))",
            ^p_long,
            ^p_lat,
            ^point_wkt
          ),
        limit: 1
      )

    case Repo.one(query) do
      nil -> 0.0
      distance -> distance
    end
  end

  @doc """
  Lists providers within their service radius of a given location.

  This function checks if the location falls within each provider's configured service radius.
  Only returns active and verified providers.

  ## Arguments

    * `lat` - Latitude of the location
    * `long` - Longitude of the location

  ## Returns

    * List of providers whose service radius includes the location

  ## Examples

      iex> list_providers_covering_location(41.8781, -87.6298)
      [%Provider{service_radius_km: 15}, ...]

  """
  def list_providers_covering_location(lat, long) do
    point_wkt = "POINT(#{long} #{lat})"

    from(p in Provider,
      where: p.is_active == true,
      where: p.is_verified == true,
      where: not is_nil(p.latitude),
      where: not is_nil(p.longitude),
      where:
        fragment(
          "ST_Distance_Sphere(ST_MakePoint(?, ?), ST_GeomFromText(?, 4326)) <= ? * 1000",
          p.longitude,
          p.latitude,
          ^point_wkt,
          p.service_radius_km
        ),
      order_by: [desc: p.rating],
      preload: [:user]
    )
    |> Repo.all()
  end

  @doc """
  Finds the nearest provider to a given location.

  Only considers active and verified providers.

  ## Arguments

    * `lat` - Latitude of the location
    * `long` - Longitude of the location

  ## Returns

    * `{:ok, provider}` if found
    * `{:error, :not_found}` if no providers available

  ## Examples

      iex> find_nearest_provider(41.8781, -87.6298)
      {:ok, %Provider{}}

  """
  def find_nearest_provider(lat, long) do
    point_wkt = "POINT(#{long} #{lat})"

    provider =
      from(p in Provider,
        where: p.is_active == true,
        where: p.is_verified == true,
        where: not is_nil(p.latitude),
        where: not is_nil(p.longitude),
        order_by:
          fragment(
            "ST_Distance_Sphere(ST_MakePoint(?, ?), ST_GeomFromText(?, 4326)) ASC",
            p.longitude,
            p.latitude,
            ^point_wkt
          ),
        limit: 1,
        preload: [:user]
      )
      |> Repo.one()

    case provider do
      nil -> {:error, :not_found}
      provider -> {:ok, provider}
    end
  end

  # Stripe Connect Integration

  @doc """
  Creates a Stripe Connect Express account for a provider.

  This function creates a Stripe Connect Express account and stores the account ID
  in the provider record. The provider can then complete onboarding via Stripe's
  hosted onboarding flow.

  ## Arguments

    * `provider_id` - UUID of the provider

  ## Returns

    * `{:ok, provider}` on success with stripe_account_id set
    * `{:error, reason}` if Stripe API call fails

  ## Examples

      iex> create_stripe_connected_account(provider_id)
      {:ok, %Provider{stripe_account_id: "acct_..."}}

  """
  def create_stripe_connected_account(provider_id) do
    provider = get_provider_with_user!(provider_id)

    # Create Stripe Connect Express account
    case create_stripe_account(provider) do
      {:ok, account_id} ->
        provider
        |> Provider.changeset(%{
          stripe_account_id: account_id,
          payout_method: :stripe
        })
        |> Repo.update()
        |> tap(&log_stripe_account_created/1)

      {:error, reason} ->
        Logger.error("Failed to create Stripe account", %{
          provider_id: provider_id,
          reason: inspect(reason)
        })

        {:error, reason}
    end
  end

  # Private helper to call Stripe API
  defp create_stripe_account(provider) do
    # Build account parameters - using minimal required fields for Express accounts
    params = %{
      type: :express,
      country: "US",
      email: provider.user.email
    }

    # Call Stripe API
    case Stripe.Account.create(params) do
      {:ok, %Stripe.Account{id: account_id}} ->
        {:ok, account_id}

      {:error, %Stripe.Error{} = error} ->
        {:error, error.message}
    end
  end

  @doc """
  Generates a Stripe Connect account link for provider onboarding.

  This creates a temporary link that redirects the provider to Stripe's hosted
  onboarding flow where they can complete their account setup.

  ## Arguments

    * `provider_id` - UUID of the provider
    * `return_url` - URL to redirect to after successful onboarding
    * `refresh_url` - URL to redirect to if the link expires

  ## Returns

    * `{:ok, account_link_url}` on success
    * `{:error, reason}` if Stripe API call fails

  ## Examples

      iex> create_stripe_account_link(provider_id, "https://example.com/return", "https://example.com/refresh")
      {:ok, "https://connect.stripe.com/setup/..."}

  """
  def create_stripe_account_link(provider_id, return_url, refresh_url) do
    provider = get_provider!(provider_id)

    if is_nil(provider.stripe_account_id) do
      {:error, "Provider does not have a Stripe account"}
    else
      params = %{
        account: provider.stripe_account_id,
        refresh_url: refresh_url,
        return_url: return_url,
        type: :account_onboarding
      }

      case Stripe.AccountLink.create(params) do
        {:ok, %Stripe.AccountLink{url: url}} ->
          {:ok, url}

        {:error, %Stripe.Error{} = error} ->
          Logger.error("Failed to create Stripe account link", %{
            provider_id: provider_id,
            error: error.message
          })

          {:error, error.message}
      end
    end
  end

  @doc """
  Checks if a provider's Stripe account is fully onboarded.

  ## Arguments

    * `provider_id` - UUID of the provider

  ## Returns

    * `{:ok, true}` if account is fully onboarded
    * `{:ok, false}` if account needs more information
    * `{:error, reason}` if check fails

  ## Examples

      iex> check_stripe_account_status(provider_id)
      {:ok, true}

  """
  def check_stripe_account_status(provider_id) do
    provider = get_provider!(provider_id)

    if is_nil(provider.stripe_account_id) do
      {:ok, false}
    else
      case Stripe.Account.retrieve(provider.stripe_account_id) do
        {:ok, %Stripe.Account{charges_enabled: charges_enabled, payouts_enabled: payouts_enabled}} ->
          {:ok, charges_enabled and payouts_enabled}

        {:error, %Stripe.Error{} = error} ->
          Logger.error("Failed to retrieve Stripe account", %{
            provider_id: provider_id,
            error: error.message
          })

          {:error, error.message}
      end
    end
  end

  defp log_stripe_account_created({:ok, provider}) do
    Logger.info("Stripe Connect account created", %{
      provider_id: provider.id,
      stripe_account_id: provider.stripe_account_id
    })

    {:ok, provider}
  end

  defp log_stripe_account_created(error), do: error

  # Provider Subscription Management

  @doc """
  Subscribes a provider to the premium plan.

  Creates a Stripe recurring subscription for $49/month and sets the is_premium flag.
  The provider must have a valid Stripe customer ID.

  ## Arguments

    * `provider_id` - UUID of the provider
    * `stripe_customer_id` - Stripe customer ID for the provider's user

  ## Returns

    * `{:ok, provider}` on success with is_premium set to true
    * `{:error, reason}` if subscription creation fails

  ## Examples

      iex> subscribe_to_premium(provider_id, "cus_...")
      {:ok, %Provider{is_premium: true, stripe_subscription_id: "sub_..."}}

  """
  def subscribe_to_premium(provider_id, stripe_customer_id) do
    provider = get_provider!(provider_id)

    # Get the premium price ID from config
    premium_price_id =
      Application.get_env(:tire_dispatch, :stripe_premium_price_id, "price_premium")

    # Create subscription
    case create_stripe_subscription(stripe_customer_id, premium_price_id) do
      {:ok, subscription_id} ->
        provider
        |> Provider.changeset(%{
          is_premium: true,
          stripe_subscription_id: subscription_id
        })
        |> Repo.update()
        |> tap(&log_premium_subscription_created/1)

      {:error, reason} ->
        Logger.error("Failed to create premium subscription", %{
          provider_id: provider_id,
          reason: inspect(reason)
        })

        {:error, reason}
    end
  end

  # Private helper to create Stripe subscription
  defp create_stripe_subscription(customer_id, price_id) do
    params = %{
      customer: customer_id,
      items: [%{price: price_id}],
      payment_behavior: :default_incomplete,
      payment_settings: %{save_default_payment_method: :on_subscription},
      expand: ["latest_invoice.payment_intent"]
    }

    case Stripe.Subscription.create(params) do
      {:ok, %Stripe.Subscription{id: subscription_id}} ->
        {:ok, subscription_id}

      {:error, %Stripe.Error{} = error} ->
        {:error, error.message}
    end
  end

  @doc """
  Cancels a provider's premium subscription.

  Cancels the Stripe subscription and sets is_premium to false at the end of the
  current billing period.

  ## Arguments

    * `provider_id` - UUID of the provider

  ## Returns

    * `{:ok, provider}` on success
    * `{:error, reason}` if cancellation fails

  ## Examples

      iex> cancel_premium_subscription(provider_id)
      {:ok, %Provider{is_premium: false}}

  """
  def cancel_premium_subscription(provider_id) do
    provider = get_provider!(provider_id)

    if is_nil(provider.stripe_subscription_id) do
      {:error, "Provider does not have an active subscription"}
    else
      case cancel_stripe_subscription(provider.stripe_subscription_id) do
        :ok ->
          # Note: We keep is_premium true until the subscription period ends
          # The webhook will handle setting it to false at period end
          Logger.info("Premium subscription cancelled", %{
            provider_id: provider_id,
            subscription_id: provider.stripe_subscription_id
          })

          {:ok, provider}

        {:error, reason} ->
          Logger.error("Failed to cancel premium subscription", %{
            provider_id: provider_id,
            reason: inspect(reason)
          })

          {:error, reason}
      end
    end
  end

  # Private helper to cancel Stripe subscription
  defp cancel_stripe_subscription(subscription_id) do
    # Cancel at period end to allow provider to use premium features until billing cycle ends
    params = %{cancel_at_period_end: true}

    case Stripe.Subscription.update(subscription_id, params) do
      {:ok, _subscription} ->
        :ok

      {:error, %Stripe.Error{} = error} ->
        {:error, error.message}
    end
  end

  @doc """
  Handles Stripe webhook events for subscription changes.

  This function should be called from the webhook controller to process
  subscription lifecycle events.

  ## Arguments

    * `event_type` - Stripe event type (e.g., "customer.subscription.deleted")
    * `subscription_data` - Subscription data from Stripe webhook

  ## Returns

    * `:ok` on success
    * `{:error, reason}` if processing fails

  ## Examples

      iex> handle_subscription_webhook("customer.subscription.deleted", %{id: "sub_..."})
      :ok

  """
  def handle_subscription_webhook(event_type, subscription_data)

  def handle_subscription_webhook("customer.subscription.deleted", %{"id" => subscription_id}) do
    # Find provider by subscription ID and downgrade to standard tier
    case Repo.get_by(Provider, stripe_subscription_id: subscription_id) do
      nil ->
        Logger.warning("Subscription deleted for unknown provider", %{
          subscription_id: subscription_id
        })

        :ok

      provider ->
        provider
        |> Provider.changeset(%{
          is_premium: false,
          stripe_subscription_id: nil
        })
        |> Repo.update()
        |> tap(&log_premium_downgraded/1)

        :ok
    end
  end

  def handle_subscription_webhook("customer.subscription.updated", %{
        "id" => subscription_id,
        "status" => status
      }) do
    # Handle subscription status changes (e.g., payment failed)
    case Repo.get_by(Provider, stripe_subscription_id: subscription_id) do
      nil ->
        Logger.warning("Subscription updated for unknown provider", %{
          subscription_id: subscription_id
        })

        :ok

      provider ->
        # If subscription is no longer active, downgrade provider
        if status in ["canceled", "unpaid", "past_due"] do
          provider
          |> Provider.changeset(%{is_premium: false})
          |> Repo.update()
          |> tap(&log_premium_downgraded/1)
        end

        :ok
    end
  end

  def handle_subscription_webhook(_event_type, _data) do
    # Ignore other webhook events
    :ok
  end

  @doc """
  Checks if a provider has an active premium subscription.

  ## Arguments

    * `provider_id` - UUID of the provider

  ## Returns

    * `true` if provider has active premium subscription
    * `false` otherwise

  ## Examples

      iex> premium?(provider_id)
      true

  """
  def premium?(provider_id) do
    provider = get_provider!(provider_id)
    provider.is_premium
  end

  defp log_premium_subscription_created({:ok, provider}) do
    Logger.info("Premium subscription created", %{
      provider_id: provider.id,
      subscription_id: provider.stripe_subscription_id
    })

    {:ok, provider}
  end

  defp log_premium_subscription_created(error), do: error

  defp log_premium_downgraded({:ok, provider}) do
    Logger.info("Provider downgraded from premium", %{
      provider_id: provider.id
    })

    {:ok, provider}
  end

  defp log_premium_downgraded(error), do: error
end
