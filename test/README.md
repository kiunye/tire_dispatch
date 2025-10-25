# Test Suite Documentation

## Overview

This directory contains the comprehensive test suite for the Tire Dispatch platform. The tests are organized by context and use ExMachina for factories and Mox for external API mocking.

## Test Environment Setup

### Dependencies

- **ExMachina**: Factory library for generating test data
- **Faker**: Generates realistic fake data
- **Mox**: Mock library for external APIs
- **StreamData**: Property-based testing (for pricing tests)

### Configuration

The test environment is configured in `config/test.exs`:

- Database: Separate test database with SQL Sandbox
- Oban: Manual testing mode (no background jobs)
- External APIs: Mocked via Mox
- Logging: Warning level only

### PostGIS Support

PostGIS geometry types are configured via `TireDispatch.PostgresTypes` module, which extends Postgrex with Geo.PostGIS.Extension.

## Test Support Files

### Factories (`test/support/factory.ex`)

ExMachina factories for all major schemas:

**User Factories:**
- `user_factory` - Basic user with driver role
- `driver_factory` - Driver user
- `provider_user_factory` - Provider user
- `admin_factory` - Admin user
- `unconfirmed_user_factory` - Unconfirmed user

**Provider Factories:**
- `provider_factory` - Verified provider with Stripe payout
- `unverified_provider_factory` - Unverified provider
- `premium_provider_factory` - Premium subscription provider
- `mpesa_provider_factory` - Provider with MPESA payout

**Job Factories:**
- `job_factory` - Open job with standard urgency
- `accepted_job_factory` - Job accepted by provider
- `en_route_job_factory` - Provider traveling to job
- `on_site_job_factory` - Provider on site
- `completed_job_factory` - Completed job with photos
- `cancelled_job_factory` - Cancelled job
- `rush_job_factory` - Rush urgency job
- `emergency_job_factory` - Emergency urgency job

**Transaction Factories:**
- `transaction_factory` - Pending payment transaction
- `completed_payment_factory` - Completed Stripe payment
- `failed_payment_factory` - Failed payment
- `mpesa_payment_factory` - MPESA payment
- `payout_factory` - Pending payout
- `completed_payout_factory` - Completed payout
- `mpesa_payout_factory` - MPESA payout
- `refund_factory` - Pending refund
- `completed_refund_factory` - Completed refund

### Mocks (`test/support/mocks.ex`)

Mox definitions for external APIs:

- `TireDispatch.StripeAPIMock` - Stripe API operations
- `TireDispatch.GoogleMapsAPIMock` - Google Maps Distance Matrix API
- `TireDispatch.AfricasTalkingAPIMock` - AfricasTalking SMS API
- `TireDispatch.MPESAAPIMock` - MPESA (Safaricom Daraja) API
- `TireDispatch.S3Mock` - AWS S3 operations

### Test Cases

**DataCase (`test/support/data_case.ex`):**
- For tests requiring database access
- Includes ExMachina and Mox imports
- Configures SQL Sandbox

**ConnCase (`test/support/conn_case.ex`):**
- For controller and integration tests
- Includes connection helpers
- User authentication helpers

**ChannelCase (`test/support/channel_case.ex`):**
- For Phoenix Channel tests
- Real-time communication testing

## Usage Examples

### Using Factories

```elixir
# In your test file
use TireDispatch.DataCase

test "creates a job" do
  driver = insert(:driver)
  job = insert(:job, driver: driver)
  
  assert job.status == :open
  assert job.driver_id == driver.id
end

# Build without inserting
job = build(:job)

# Build with overrides
job = build(:job, urgency_tier: :emergency)

# Insert with associations
job = insert(:accepted_job)  # Automatically creates driver and provider
```

### Using Mocks

```elixir
use TireDispatch.DataCase
import Mox

setup :verify_on_exit!

test "processes Stripe payment" do
  # Set up mock expectation
  expect(TireDispatch.StripeAPIMock, :create_checkout_session, fn params ->
    {:ok, %{id: "cs_test_123", url: "https://checkout.stripe.com/..."}}
  end)
  
  # Call code that uses the mock
  {:ok, session} = Payments.initiate_stripe_checkout(job_id, 3500)
  
  assert session.id == "cs_test_123"
end
```

### Testing with PostGIS

```elixir
test "finds jobs within radius" do
  # Create job with location
  job = insert(:job)
  
  # Query jobs within 10km
  jobs = Jobs.jobs_within_radius(-1.2921, 36.8219, 10)
  
  assert job.id in Enum.map(jobs, & &1.id)
end
```

## Running Tests

```bash
# Run all tests
mix test

# Run specific test file
mix test test/tire_dispatch/jobs_test.exs

# Run specific test
mix test test/tire_dispatch/jobs_test.exs:42

# Run with coverage
mix test --cover

# Run failed tests only
mix test --failed

# Run tests matching pattern
mix test --only integration
```

## Test Organization

```
test/
├── support/
│   ├── factory.ex              # ExMachina factories
│   ├── mocks.ex                # Mox definitions
│   ├── data_case.ex            # Database test case
│   ├── conn_case.ex            # Connection test case
│   ├── channel_case.ex         # Channel test case
│   └── fixtures/
│       └── users_fixtures.ex   # User-specific fixtures
├── tire_dispatch/
│   ├── jobs_test.exs           # Jobs context tests
│   ├── payments_test.exs       # Payments context tests
│   ├── providers_test.exs      # Providers context tests
│   ├── pricing_test.exs        # Pricing context tests
│   ├── users_test.exs          # Users context tests
│   └── analytics_test.exs      # Analytics context tests
├── tire_dispatch_web/
│   ├── live/
│   │   ├── driver_dashboard_live_test.exs
│   │   ├── provider_dashboard_live_test.exs
│   │   └── admin_dashboard_live_test.exs
│   └── channels/
│       └── job_channel_test.exs
└── test_helper.exs             # Test configuration
```

## Best Practices

1. **Use factories for all test data** - Avoid manual struct creation
2. **Mock external APIs** - Never make real API calls in tests
3. **Use SQL Sandbox** - Ensures test isolation
4. **Test one thing per test** - Keep tests focused
5. **Use descriptive test names** - Explain what is being tested
6. **Set up mocks with `expect/3`** - Verify mock calls with `verify_on_exit!`
7. **Use `build` for associations** - Avoid unnecessary database inserts
8. **Test edge cases** - Include error scenarios
9. **Keep tests fast** - Use async: true when possible
10. **Document complex test setups** - Add comments for clarity

## Troubleshooting

### PostGIS Errors

If you see "type `geometry` can not be handled" errors:
- Ensure `TireDispatch.PostgresTypes` is properly configured
- Check that PostGIS extension is enabled in test database

### Mock Errors

If mocks aren't working:
- Verify `setup :verify_on_exit!` is called
- Check that behaviour modules are defined
- Ensure mock expectations match actual calls

### Database Errors

If you see ownership errors:
- Check that `use TireDispatch.DataCase` is present
- Verify SQL Sandbox is configured in test_helper.exs
- Ensure tests aren't running async when they shouldn't

## Next Steps

After setting up the test environment:

1. Write unit tests for all contexts (Task 17.2)
2. Write LiveView integration tests (Task 17.3)
3. Write Channel tests (Task 17.4)
4. Write Oban worker tests (Task 17.5)
5. Write property-based tests for pricing (Task 17.6)
