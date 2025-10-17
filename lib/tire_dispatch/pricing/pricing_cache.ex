defmodule TireDispatch.Pricing.PricingCache do
  @moduledoc """
  ETS-based cache for pricing rules to enable sub-millisecond lookups.
  """

  use GenServer
  require Logger

  @table_name :pricing_rules_cache

  # Client API

  @doc """
  Starts the PricingCache GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Initializes the ETS cache with all active pricing rules from the database.
  """
  def init do
    GenServer.call(__MODULE__, :init)
  end

  @doc """
  Gets a pricing rule from the cache by ID.

  Returns `{:ok, rule}` if found, `{:error, :not_found}` otherwise.

  ## Examples

      iex> get_rule(123)
      {:ok, %PricingRule{}}

      iex> get_rule(999)
      {:error, :not_found}

  """
  def get_rule(rule_id) do
    case :ets.lookup(@table_name, rule_id) do
      [{^rule_id, rule}] -> {:ok, rule}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Sets a pricing rule in the cache.

  ## Examples

      iex> set_rule(123, %PricingRule{id: 123})
      :ok

  """
  def set_rule(rule_id, rule) do
    :ets.insert(@table_name, {rule_id, rule})
    :ok
  end

  @doc """
  Deletes a pricing rule from the cache.

  ## Examples

      iex> delete_rule(123)
      :ok

  """
  def delete_rule(rule_id) do
    :ets.delete(@table_name, rule_id)
    :ok
  end

  @doc """
  Refreshes all pricing rules in the cache from the database.

  ## Examples

      iex> refresh_all()
      :ok

  """
  def refresh_all do
    GenServer.call(__MODULE__, :refresh_all)
  end

  @doc """
  Gets all active pricing rules from the cache.

  Returns a list of pricing rules.

  ## Examples

      iex> get_all_active()
      [%PricingRule{}, ...]

  """
  def get_all_active do
    @table_name
    |> :ets.tab2list()
    |> Enum.map(fn {_id, rule} -> rule end)
    |> Enum.filter(& &1.active)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table with public read access
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])

    # Load all pricing rules into cache
    load_pricing_rules()

    Logger.info("PricingCache initialized with ETS table")

    {:ok, %{}}
  end

  @impl true
  def handle_call(:init, _from, state) do
    load_pricing_rules()
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:refresh_all, _from, state) do
    # Clear existing cache
    :ets.delete_all_objects(@table_name)

    # Reload all pricing rules
    load_pricing_rules()

    Logger.info("PricingCache refreshed")

    {:reply, :ok, state}
  end

  # Private Functions

  defp load_pricing_rules do
    alias TireDispatch.Pricing

    pricing_rules = Pricing.list_pricing_rules()

    Enum.each(pricing_rules, fn rule ->
      :ets.insert(@table_name, {rule.id, rule})
    end)

    Logger.debug("Loaded #{length(pricing_rules)} pricing rules into cache")
  end
end
