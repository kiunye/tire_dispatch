defmodule TireDispatch.Notifications.AfricasTalkingAPI do
  @moduledoc """
  Behaviour for AfricasTalking SMS API interactions.
  """

  @callback send_sms(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback send_bulk_sms(list(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
end
