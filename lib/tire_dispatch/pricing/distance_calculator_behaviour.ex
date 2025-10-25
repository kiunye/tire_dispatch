defmodule TireDispatch.Pricing.DistanceCalculatorBehaviour do
  @moduledoc """
  Behaviour for distance calculation services.
  """

  @callback calculate_distance_factor(map()) :: {:ok, float()} | {:error, term()}
end
