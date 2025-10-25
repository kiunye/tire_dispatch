defmodule TireDispatch.Pricing.GoogleMapsAPI do
  @moduledoc """
  Behaviour for Google Maps Distance Matrix API interactions.
  """

  @callback get_distance(float(), float(), float(), float()) ::
              {:ok, map()} | {:error, term()}
end
