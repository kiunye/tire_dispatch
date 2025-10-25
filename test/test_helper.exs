# Define mocks for external services
Mox.defmock(TireDispatch.Pricing.DistanceCalculatorMock,
  for: TireDispatch.Pricing.DistanceCalculatorBehaviour
)

# Start ExUnit
ExUnit.start()

# Configure Ecto Sandbox
Ecto.Adapters.SQL.Sandbox.mode(TireDispatch.Repo, :manual)
