defmodule TireDispatch.Payments.StripeAPI do
  @moduledoc """
  Behaviour for Stripe API interactions.
  """

  @callback create_checkout_session(map()) :: {:ok, map()} | {:error, term()}
  @callback create_connected_account(map()) :: {:ok, map()} | {:error, term()}
  @callback create_transfer(map()) :: {:ok, map()} | {:error, term()}
  @callback create_refund(map()) :: {:ok, map()} | {:error, term()}
  @callback create_subscription(map()) :: {:ok, map()} | {:error, term()}
  @callback cancel_subscription(String.t()) :: {:ok, map()} | {:error, term()}
  @callback construct_webhook_event(String.t(), String.t(), String.t()) ::
              {:ok, map()} | {:error, term()}
end
