defmodule TireDispatch.Mocks do
  @moduledoc """
  Mox definitions for external API mocking in tests.
  """

  # Stripe API Mock
  Mox.defmock(TireDispatch.StripeAPIMock, for: TireDispatch.Payments.StripeAPI)

  # Google Maps API Mock
  Mox.defmock(TireDispatch.GoogleMapsAPIMock, for: TireDispatch.Pricing.GoogleMapsAPI)

  # AfricasTalking API Mock
  Mox.defmock(TireDispatch.AfricasTalkingAPIMock, for: TireDispatch.Notifications.AfricasTalkingAPI)

  # MPESA API Mock
  Mox.defmock(TireDispatch.MPESAAPIMock, for: TireDispatch.Payments.MPESAAPI)

  # AWS S3 Mock
  Mox.defmock(TireDispatch.S3Mock, for: TireDispatch.Photos.S3Client)
end
