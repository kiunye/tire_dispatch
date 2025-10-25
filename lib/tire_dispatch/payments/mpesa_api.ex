defmodule TireDispatch.Payments.MPESAAPI do
  @moduledoc """
  Behaviour for MPESA (Safaricom Daraja) API interactions.
  """

  @callback generate_access_token() :: {:ok, String.t()} | {:error, term()}
  @callback initiate_stk_push(String.t(), integer(), String.t(), String.t()) ::
              {:ok, map()} | {:error, term()}
  @callback query_transaction_status(String.t()) :: {:ok, map()} | {:error, term()}
  @callback initiate_b2c_payment(String.t(), integer(), String.t()) ::
              {:ok, map()} | {:error, term()}
  @callback initiate_reversal(String.t(), integer(), String.t()) ::
              {:ok, map()} | {:error, term()}
end
