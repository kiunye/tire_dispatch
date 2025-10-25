defmodule TireDispatchWeb.AdminDashboardLive do
  use TireDispatchWeb, :live_view

  alias TireDispatch.{Analytics, Jobs, Pricing, Providers}

  @impl true
  def mount(_params, session, socket) do
    current_scope = session["current_scope"]

    case current_scope do
      %{role: :admin} = scope ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(TireDispatch.PubSub, "admin:jobs")
        end

        # Load initial data
        jobs = load_jobs_by_status()
        providers = Providers.list_providers()

        # Get KPIs for last 30 days
        end_date = Date.utc_today()
        start_date = Date.add(end_date, -30)
        kpis = Analytics.get_platform_kpis(%{start_date: start_date, end_date: end_date})

        pricing_rules = Pricing.list_pricing_rules()

        {:ok,
         assign(socket,
           current_scope: scope,
           jobs: jobs,
           providers: providers,
           kpis: kpis,
           pricing_rules: pricing_rules,
           selected_job: nil,
           active_tab: :jobs,
           page_title: "Admin Dashboard"
         )}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "You must be an admin to access this page")
         |> redirect(to: ~p"/")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="min-h-screen bg-slate-900">
        <!-- Header -->
        <div class="bg-slate-800 border-b border-slate-700">
          <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
            <div class="flex items-center justify-between">
              <div>
                <h1 class="text-2xl font-bold text-slate-100">Admin Dashboard</h1>
                <p class="text-sm text-slate-400 mt-1">Platform monitoring and management</p>
              </div>
              <div class="flex items-center space-x-4">
                <span class="text-sm text-slate-400">
                  Welcome, <span class="text-slate-100 font-medium">{@current_scope.email}</span>
                </span>
              </div>
            </div>
          </div>
        </div>
        
    <!-- KPI Cards -->
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
            <!-- Total Jobs KPI -->
            <div class="bg-slate-800 border border-slate-700 rounded-xl p-6">
              <div class="flex items-center justify-between">
                <div>
                  <p class="text-sm font-medium text-slate-400">Total Jobs</p>
                  <p class="text-3xl font-bold text-slate-100 mt-2">
                    {Map.get(@kpis, :total_jobs, 0)}
                  </p>
                </div>
                <div class="w-12 h-12 bg-gradient-to-br from-blue-500 to-cyan-500 rounded-full flex items-center justify-center">
                  <.icon name="hero-briefcase" class="w-6 h-6 text-white" />
                </div>
              </div>
            </div>
            
    <!-- Revenue KPI -->
            <div class="bg-slate-800 border border-slate-700 rounded-xl p-6">
              <div class="flex items-center justify-between">
                <div>
                  <p class="text-sm font-medium text-slate-400">Total Revenue</p>
                  <p class="text-3xl font-bold text-slate-100 mt-2">
                    ${format_currency(Map.get(@kpis, :total_revenue_cents, 0))}
                  </p>
                </div>
                <div class="w-12 h-12 bg-gradient-to-br from-emerald-500 to-green-500 rounded-full flex items-center justify-center">
                  <.icon name="hero-currency-dollar" class="w-6 h-6 text-white" />
                </div>
              </div>
            </div>
            
    <!-- Average Response Time KPI -->
            <div class="bg-slate-800 border border-slate-700 rounded-xl p-6">
              <div class="flex items-center justify-between">
                <div>
                  <p class="text-sm font-medium text-slate-400">Avg Response Time</p>
                  <p class="text-3xl font-bold text-slate-100 mt-2">
                    {format_minutes(Map.get(@kpis, :avg_response_time_minutes, 0))}
                  </p>
                </div>
                <div class="w-12 h-12 bg-gradient-to-br from-purple-500 to-indigo-500 rounded-full flex items-center justify-center">
                  <.icon name="hero-clock" class="w-6 h-6 text-white" />
                </div>
              </div>
            </div>
            
    <!-- Provider Utilization KPI -->
            <div class="bg-slate-800 border border-slate-700 rounded-xl p-6">
              <div class="flex items-center justify-between">
                <div>
                  <p class="text-sm font-medium text-slate-400">Provider Utilization</p>
                  <p class="text-3xl font-bold text-slate-100 mt-2">
                    {format_percentage(Map.get(@kpis, :provider_utilization, 0))}
                  </p>
                </div>
                <div class="w-12 h-12 bg-gradient-to-br from-amber-500 to-orange-500 rounded-full flex items-center justify-center">
                  <.icon name="hero-chart-bar" class="w-6 h-6 text-white" />
                </div>
              </div>
            </div>
          </div>
          
    <!-- Tabs -->
          <div class="bg-slate-800 border border-slate-700 rounded-xl overflow-hidden">
            <div class="border-b border-slate-700">
              <nav class="flex space-x-8 px-6" aria-label="Tabs">
                <button
                  phx-click="change_tab"
                  phx-value-tab="jobs"
                  class={[
                    "py-4 px-1 border-b-2 font-medium text-sm transition-colors",
                    if(@active_tab == :jobs,
                      do: "border-cyan-500 text-cyan-500",
                      else:
                        "border-transparent text-slate-400 hover:text-slate-300 hover:border-slate-300"
                    )
                  ]}
                >
                  Jobs
                </button>
                <button
                  phx-click="change_tab"
                  phx-value-tab="providers"
                  class={[
                    "py-4 px-1 border-b-2 font-medium text-sm transition-colors",
                    if(@active_tab == :providers,
                      do: "border-cyan-500 text-cyan-500",
                      else:
                        "border-transparent text-slate-400 hover:text-slate-300 hover:border-slate-300"
                    )
                  ]}
                >
                  Providers
                </button>
                <button
                  phx-click="change_tab"
                  phx-value-tab="pricing"
                  class={[
                    "py-4 px-1 border-b-2 font-medium text-sm transition-colors",
                    if(@active_tab == :pricing,
                      do: "border-cyan-500 text-cyan-500",
                      else:
                        "border-transparent text-slate-400 hover:text-slate-300 hover:border-slate-300"
                    )
                  ]}
                >
                  Pricing Rules
                </button>
                <button
                  phx-click="change_tab"
                  phx-value-tab="analytics"
                  class={[
                    "py-4 px-1 border-b-2 font-medium text-sm transition-colors",
                    if(@active_tab == :analytics,
                      do: "border-cyan-500 text-cyan-500",
                      else:
                        "border-transparent text-slate-400 hover:text-slate-300 hover:border-slate-300"
                    )
                  ]}
                >
                  Analytics
                </button>
              </nav>
            </div>
            
    <!-- Tab Content -->
            <div class="p-6">
              <%= cond do %>
                <% @active_tab == :jobs -> %>
                  <.jobs_tab jobs={@jobs} selected_job={@selected_job} />
                <% @active_tab == :providers -> %>
                  <.providers_tab providers={@providers} />
                <% @active_tab == :pricing -> %>
                  <.pricing_tab pricing_rules={@pricing_rules} />
                <% @active_tab == :analytics -> %>
                  <.analytics_tab kpis={@kpis} />
                <% true -> %>
                  <div class="text-slate-400">Select a tab</div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Jobs Tab Component
  defp jobs_tab(assigns) do
    ~H"""
    <div>
      <h3 class="text-lg font-semibold text-slate-100 mb-4">Job Monitoring</h3>
      
    <!-- Job Status Columns -->
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6 gap-4">
        <%= for status <- [:open, :accepted, :en_route, :on_site, :completed, :cancelled] do %>
          <div class="bg-slate-900 rounded-lg p-4">
            <div class="flex items-center justify-between mb-3">
              <h4 class={["text-sm font-medium capitalize", status_text_color(status)]}>
                {status_label(status)}
              </h4>
              <span class={[
                "px-2 py-1 text-xs font-medium rounded-full",
                status_badge_color(status)
              ]}>
                {length(Map.get(@jobs, status, []))}
              </span>
            </div>

            <div class="space-y-2">
              <%= for job <- Map.get(@jobs, status, []) do %>
                <button
                  phx-click="view_job_details"
                  phx-value-job-id={job.id}
                  class="w-full text-left bg-slate-800 hover:bg-slate-700 rounded-lg p-3 transition-colors"
                >
                  <div class="text-xs text-slate-400 mb-1">
                    Job #{String.slice(job.id, 0..7)}
                  </div>
                  <div class="text-sm text-slate-200 font-medium capitalize">
                    {format_service_type(job.service_type)}
                  </div>
                  <div class="text-xs text-slate-400 mt-1">
                    {format_time_ago(job.inserted_at)}
                  </div>
                </button>
              <% end %>

              <%= if Enum.empty?(Map.get(@jobs, status, [])) do %>
                <div class="text-xs text-slate-500 text-center py-4">
                  No {status_label(status)} jobs
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
      
    <!-- Selected Job Details -->
      <%= if @selected_job do %>
        <div class="mt-6 bg-slate-900 rounded-lg p-6">
          <h4 class="text-lg font-semibold text-slate-100 mb-4">Job Details</h4>
          <.job_details job={@selected_job} />
        </div>
      <% end %>
    </div>
    """
  end

  # Providers Tab Component
  defp providers_tab(assigns) do
    ~H"""
    <div>
      <h3 class="text-lg font-semibold text-slate-100 mb-4">Provider Management</h3>

      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-slate-700">
          <thead class="bg-slate-800">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-slate-300 uppercase tracking-wider">
                Provider
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-slate-300 uppercase tracking-wider">
                Rating
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-slate-300 uppercase tracking-wider">
                Status
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-slate-300 uppercase tracking-wider">
                Verified
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-slate-300 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody class="bg-slate-900 divide-y divide-slate-700">
            <%= for provider <- @providers do %>
              <tr class="hover:bg-slate-800 transition-colors">
                <td class="px-6 py-4 whitespace-nowrap">
                  <div class="flex items-center">
                    <div class="w-10 h-10 bg-gradient-to-br from-blue-500 to-cyan-500 rounded-full flex items-center justify-center">
                      <span class="text-white font-semibold text-sm">
                        {get_initials(provider)}
                      </span>
                    </div>
                    <div class="ml-4">
                      <div class="text-sm font-medium text-slate-100">
                        Provider #{String.slice(provider.id, 0..7)}
                      </div>
                      <div class="text-sm text-slate-400">
                        {provider.vehicle_type}
                      </div>
                    </div>
                  </div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <div class="flex items-center">
                    <.icon name="hero-star-solid" class="w-4 h-4 text-amber-500 mr-1" />
                    <span class="text-sm text-slate-100">
                      {format_rating(provider.rating)}
                    </span>
                  </div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <span class={[
                    "px-2 py-1 text-xs font-medium rounded-full",
                    if(provider.is_active,
                      do: "bg-emerald-500/10 text-emerald-400",
                      else: "bg-slate-700 text-slate-400"
                    )
                  ]}>
                    {if provider.is_active, do: "Active", else: "Inactive"}
                  </span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <%= if provider.is_verified do %>
                    <span class="px-2 py-1 text-xs font-medium rounded-full bg-cyan-500/10 text-cyan-400">
                      <.icon name="hero-check-badge-solid" class="w-4 h-4 inline mr-1" /> Verified
                    </span>
                  <% else %>
                    <span class="px-2 py-1 text-xs font-medium rounded-full bg-slate-700 text-slate-400">
                      Not Verified
                    </span>
                  <% end %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm">
                  <%= if !provider.is_verified do %>
                    <button
                      phx-click="verify_provider"
                      phx-value-provider-id={provider.id}
                      class="text-cyan-400 hover:text-cyan-300 font-medium"
                    >
                      Verify
                    </button>
                  <% end %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  # Pricing Tab Component
  defp pricing_tab(assigns) do
    ~H"""
    <div>
      <h3 class="text-lg font-semibold text-slate-100 mb-4">Pricing Rules Configuration</h3>

      <div class="space-y-4">
        <%= for rule <- @pricing_rules do %>
          <div class="bg-slate-900 rounded-lg p-4">
            <div class="flex items-center justify-between">
              <div class="flex-1">
                <h4 class="text-sm font-medium text-slate-100">{rule.name}</h4>
                <p class="text-xs text-slate-400 mt-1">
                  Type: <span class="capitalize">{rule.rule_type}</span>
                </p>
                <p class="text-xs text-slate-400">
                  Value: <span class="text-slate-200">{format_rule_value(rule)}</span>
                </p>
              </div>
              <div class="flex items-center space-x-2">
                <span class={[
                  "px-2 py-1 text-xs font-medium rounded-full",
                  if(rule.active,
                    do: "bg-emerald-500/10 text-emerald-400",
                    else: "bg-slate-700 text-slate-400"
                  )
                ]}>
                  {if rule.active, do: "Active", else: "Inactive"}
                </span>
                <button
                  phx-click="edit_pricing_rule"
                  phx-value-rule-id={rule.id}
                  class="text-cyan-400 hover:text-cyan-300 text-sm font-medium"
                >
                  Edit
                </button>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Analytics Tab Component
  defp analytics_tab(assigns) do
    ~H"""
    <div>
      <h3 class="text-lg font-semibold text-slate-100 mb-4">Platform Analytics</h3>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <!-- Jobs by Status -->
        <div class="bg-slate-900 rounded-lg p-6">
          <h4 class="text-sm font-medium text-slate-300 mb-4">Jobs by Status</h4>
          <div class="space-y-3">
            <%= for {status, count} <- Map.get(@kpis, :jobs_by_status, %{}) do %>
              <div class="flex items-center justify-between">
                <span class={["text-sm capitalize", status_text_color(status)]}>
                  {status_label(status)}
                </span>
                <span class="text-sm font-medium text-slate-100">{count}</span>
              </div>
            <% end %>
          </div>
        </div>
        
    <!-- Revenue Breakdown -->
        <div class="bg-slate-900 rounded-lg p-6">
          <h4 class="text-sm font-medium text-slate-300 mb-4">Revenue Breakdown</h4>
          <div class="space-y-3">
            <div class="flex items-center justify-between">
              <span class="text-sm text-slate-400">Total Revenue</span>
              <span class="text-sm font-medium text-slate-100">
                ${format_currency(Map.get(@kpis, :total_revenue_cents, 0))}
              </span>
            </div>
            <div class="flex items-center justify-between">
              <span class="text-sm text-slate-400">Platform Commission</span>
              <span class="text-sm font-medium text-slate-100">
                ${format_currency(Map.get(@kpis, :platform_commission_cents, 0))}
              </span>
            </div>
            <div class="flex items-center justify-between">
              <span class="text-sm text-slate-400">Provider Payouts</span>
              <span class="text-sm font-medium text-slate-100">
                ${format_currency(Map.get(@kpis, :provider_payouts_cents, 0))}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Job Details Component
  defp job_details(assigns) do
    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
      <div>
        <h5 class="text-sm font-medium text-slate-400 mb-2">Job Information</h5>
        <dl class="space-y-2">
          <div>
            <dt class="text-xs text-slate-500">Job ID</dt>
            <dd class="text-sm text-slate-100">{@job.id}</dd>
          </div>
          <div>
            <dt class="text-xs text-slate-500">Service Type</dt>
            <dd class="text-sm text-slate-100 capitalize">
              {format_service_type(@job.service_type)}
            </dd>
          </div>
          <div>
            <dt class="text-xs text-slate-500">Status</dt>
            <dd class={["text-sm capitalize", status_text_color(@job.status)]}>
              {status_label(@job.status)}
            </dd>
          </div>
          <div>
            <dt class="text-xs text-slate-500">Urgency</dt>
            <dd class="text-sm text-slate-100 capitalize">{@job.urgency_tier}</dd>
          </div>
          <div>
            <dt class="text-xs text-slate-500">Vehicle Type</dt>
            <dd class="text-sm text-slate-100 capitalize">{@job.vehicle_type}</dd>
          </div>
        </dl>
      </div>

      <div>
        <h5 class="text-sm font-medium text-slate-400 mb-2">Actions</h5>
        <div class="space-y-2">
          <%= if @job.status in [:completed, :cancelled] do %>
            <button
              phx-click="process_refund"
              phx-value-job-id={@job.id}
              class="w-full px-4 py-2 bg-gradient-to-r from-red-500 to-rose-500 hover:from-red-600 hover:to-rose-600 text-white font-semibold rounded-lg transition-all duration-200"
            >
              Process Refund
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: String.to_existing_atom(tab))}
  end

  @impl true
  def handle_event("view_job_details", %{"job-id" => job_id}, socket) do
    job = Jobs.get_job_with_assocs!(job_id)
    {:noreply, assign(socket, selected_job: job)}
  end

  @impl true
  def handle_event("verify_provider", %{"provider-id" => provider_id}, socket) do
    case Providers.verify_provider(provider_id) do
      {:ok, _provider} ->
        providers = Providers.list_providers()

        {:noreply,
         socket
         |> put_flash(:info, "Provider verified successfully")
         |> assign(providers: providers)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to verify provider")}
    end
  end

  @impl true
  def handle_event("edit_pricing_rule", %{"rule-id" => rule_id}, socket) do
    # For now, just toggle the active status of the rule
    rule = Pricing.get_pricing_rule!(rule_id)

    case Pricing.update_pricing_rule(rule, %{active: !rule.active}) do
      {:ok, _updated_rule} ->
        # Invalidate pricing cache
        Pricing.refresh_pricing_cache()

        # Reload pricing rules
        pricing_rules = Pricing.list_pricing_rules()

        {:noreply,
         socket
         |> put_flash(:info, "Pricing rule updated successfully")
         |> assign(pricing_rules: pricing_rules)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update pricing rule")}
    end
  end

  @impl true
  def handle_event("process_refund", %{"job-id" => job_id}, socket) do
    alias TireDispatch.Payments

    # Find the payment transaction for this job
    case Payments.get_payment_transaction_for_job(job_id) do
      {:ok, transaction} ->
        case Payments.refund_payment(transaction, "Admin-initiated refund") do
          {:ok, _refund_transaction} ->
            {:noreply,
             socket
             |> put_flash(:info, "Refund processed successfully")
             |> assign(selected_job: nil)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to process refund: #{inspect(reason)}")}
        end

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "No payment transaction found for this job")}
    end
  end

  @impl true
  def handle_info({:job_created, job}, socket) do
    jobs = update_jobs_map(socket.assigns.jobs, job)
    {:noreply, assign(socket, jobs: jobs)}
  end

  @impl true
  def handle_info({:job_updated, job}, socket) do
    jobs = update_jobs_map(socket.assigns.jobs, job)

    socket =
      if socket.assigns.selected_job && socket.assigns.selected_job.id == job.id do
        assign(socket, selected_job: job)
      else
        socket
      end

    {:noreply, assign(socket, jobs: jobs)}
  end

  @impl true
  def handle_info({:job_accepted, job}, socket) do
    jobs = update_jobs_map(socket.assigns.jobs, job)
    {:noreply, assign(socket, jobs: jobs)}
  end

  @impl true
  def handle_info({:job_completed, job}, socket) do
    jobs = update_jobs_map(socket.assigns.jobs, job)
    {:noreply, assign(socket, jobs: jobs)}
  end

  @impl true
  def handle_info({:job_cancelled, job}, socket) do
    jobs = update_jobs_map(socket.assigns.jobs, job)
    {:noreply, assign(socket, jobs: jobs)}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # Helper Functions

  defp load_jobs_by_status do
    Jobs.list_all_jobs()
    |> Enum.group_by(& &1.status)
  end

  defp update_jobs_map(jobs_map, updated_job) do
    # Remove job from all status groups
    jobs_map =
      Enum.reduce(jobs_map, %{}, fn {status, jobs}, acc ->
        filtered_jobs = Enum.reject(jobs, &(&1.id == updated_job.id))
        Map.put(acc, status, filtered_jobs)
      end)

    # Add job to its current status group
    current_status_jobs = Map.get(jobs_map, updated_job.status, [])
    Map.put(jobs_map, updated_job.status, [updated_job | current_status_jobs])
  end

  defp format_currency(cents) when is_integer(cents) do
    (cents / 100) |> :erlang.float_to_binary(decimals: 2)
  end

  defp format_currency(_), do: "0.00"

  defp format_minutes(minutes) when is_number(minutes) do
    "#{round(minutes)}m"
  end

  defp format_minutes(_), do: "0m"

  defp format_percentage(value) when is_number(value) do
    "#{round(value * 100)}%"
  end

  defp format_percentage(_), do: "0%"

  defp format_rating(rating) when is_nil(rating), do: "N/A"

  defp format_rating(rating) do
    Decimal.to_float(rating) |> :erlang.float_to_binary(decimals: 1)
  end

  defp format_service_type(service_type) do
    service_type
    |> to_string()
    |> String.replace("_", " ")
  end

  defp format_rule_value(rule) do
    case rule.rule_type do
      :multiplier -> "#{Decimal.to_float(rule.value)}x"
      :base_rate -> "$#{Decimal.to_float(rule.value)}"
      _ -> to_string(rule.value)
    end
  end

  defp format_time_ago(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  defp get_initials(provider) do
    "P#{String.slice(provider.id, 0..0) |> String.upcase()}"
  end

  defp status_label(status) do
    case status do
      :en_route -> "En Route"
      :on_site -> "On Site"
      _ -> to_string(status)
    end
  end

  defp status_text_color(status) do
    case status do
      :open -> "text-blue-400"
      :accepted -> "text-cyan-400"
      :en_route -> "text-purple-400"
      :on_site -> "text-indigo-400"
      :completed -> "text-emerald-400"
      :cancelled -> "text-red-400"
      _ -> "text-slate-400"
    end
  end

  defp status_badge_color(status) do
    case status do
      :open -> "bg-blue-500/10 text-blue-400"
      :accepted -> "bg-cyan-500/10 text-cyan-400"
      :en_route -> "bg-purple-500/10 text-purple-400"
      :on_site -> "bg-indigo-500/10 text-indigo-400"
      :completed -> "bg-emerald-500/10 text-emerald-400"
      :cancelled -> "bg-red-500/10 text-red-400"
      _ -> "bg-slate-700 text-slate-400"
    end
  end
end
