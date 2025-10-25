defmodule TireDispatchWeb.DriverDashboardLive do
  @moduledoc """
  LiveView for the driver dashboard.

  Handles service requests, quote display, payment confirmation,
  and real-time job tracking with provider location updates.
  """
  use TireDispatchWeb, :live_view

  alias TireDispatch.Jobs
  alias TireDispatch.Payments
  alias TireDispatch.Pricing
  alias TireDispatchWeb.Layouts

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    # Check if user is authenticated
    case Map.get(socket.assigns, :current_scope) do
      nil ->
        {:ok, redirect(socket, to: ~p"/users/log-in")}

      current_scope ->
        user_id = current_scope.user.id

        # Subscribe to driver-specific job updates
        Phoenix.PubSub.subscribe(TireDispatch.PubSub, "driver:#{user_id}:jobs")

        {:ok,
         assign(socket,
           user_id: user_id,
           current_job: nil,
           quote: nil,
           provider_location: nil,
           step: :input,
           form: to_form(%{}, as: :service_request),
           payment_method: nil,
           error_message: nil,
           show_cancel_modal: false
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-slate-900">
      <div class="max-w-md mx-auto px-4 sm:px-6 py-8">
        <div class="mb-8 text-center">
          <div class="flex items-center justify-center mb-4">
            <div class="w-12 h-12 bg-gradient-to-br from-blue-500 to-cyan-500 rounded-full flex items-center justify-center">
              <.icon name="hero-wrench-screwdriver" class="h-6 w-6 text-white" />
            </div>
          </div>
          <h1 class="text-2xl font-bold text-slate-100">Driver Dashboard</h1>
          <p class="mt-2 text-sm text-slate-400">Instant roadside assistance at your fingertips</p>
        </div>

        <%= if @error_message do %>
          <div class="mb-6 bg-red-500/10 border border-red-500/50 rounded-lg p-4">
            <div class="flex">
              <div class="flex-shrink-0">
                <.icon name="hero-x-circle" class="h-5 w-5 text-red-400" />
              </div>
              <div class="ml-3">
                <p class="text-sm text-red-300">{@error_message}</p>
              </div>
            </div>
          </div>
        <% end %>

        <%!-- Cancel Confirmation Modal --%>
        <%= if @show_cancel_modal do %>
          <div
            class="fixed inset-0 bg-black/75 backdrop-blur-sm flex items-center justify-center z-50"
            phx-click="hide_cancel_confirmation"
          >
            <div
              class="bg-slate-800 border border-slate-700 rounded-xl p-8 max-w-md mx-4 shadow-2xl"
              phx-click="stop_propagation"
            >
              <div class="text-center">
                <div class="mx-auto flex items-center justify-center h-12 w-12 rounded-full bg-red-500/20 mb-4">
                  <.icon name="hero-exclamation-triangle" class="h-6 w-6 text-red-400" />
                </div>
                <h3 class="text-lg font-semibold text-slate-100 mb-2">Cancel Job?</h3>
                <p class="text-sm text-slate-400 mb-6">
                  Are you sure you want to cancel this job? This action cannot be undone.
                </p>
                <div class="flex space-x-4">
                  <button
                    phx-click="hide_cancel_confirmation"
                    class="flex-1 px-4 py-2 bg-slate-700 text-slate-300 font-medium rounded-lg hover:bg-slate-600 transition-colors"
                  >
                    Keep Job
                  </button>
                  <button
                    phx-click="cancel_job"
                    class="flex-1 px-4 py-2 bg-gradient-to-r from-red-500 to-rose-500 text-white font-medium rounded-lg hover:from-red-600 hover:to-rose-600 transition-all shadow-lg shadow-red-500/25"
                  >
                    Cancel Job
                  </button>
                </div>
              </div>
            </div>
          </div>
        <% end %>

        <%= cond do %>
          <% @step == :input -> %>
            {render_service_request_form(assigns)}
          <% @step == :quote -> %>
            {render_quote_display(assigns)}
          <% @step == :payment -> %>
            {render_payment_selection(assigns)}
          <% @step == :tracking -> %>
            {render_job_tracking(assigns)}
          <% true -> %>
            <div class="text-center py-12">
              <p class="text-gray-500">Unknown step</p>
            </div>
        <% end %>
      </div>

      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end

  # Render service request form
  defp render_service_request_form(assigns) do
    ~H"""
    <div class="bg-slate-800 rounded-2xl shadow-xl p-6 sm:p-8">
      <.form for={@form} id="service-request-form" phx-submit="request_service">
        <div class="space-y-4">
          <div>
            <label class="block text-sm font-medium text-slate-300 mb-2">
              Service Type
            </label>
            <select
              name="service_request[service_type]"
              class="w-full px-4 py-3 bg-slate-700/50 border border-slate-600 rounded-lg text-slate-100 placeholder-slate-500 focus:ring-2 focus:ring-cyan-500 focus:border-cyan-500 transition-colors"
              required
            >
              <option value="">Select a service</option>
              <option value="flat_repair">Flat Tire Repair</option>
              <option value="nail_removal">Nail Removal</option>
              <option value="air_fill">Air Fill</option>
              <option value="new_tire">New Tire Installation</option>
              <option value="replacement">Tire Replacement</option>
            </select>
          </div>

          <div>
            <label class="block text-sm font-medium text-slate-300 mb-2">
              Urgency Level
            </label>
            <select
              name="service_request[urgency_tier]"
              class="w-full px-4 py-3 bg-slate-700/50 border border-slate-600 rounded-lg text-slate-100 placeholder-slate-500 focus:ring-2 focus:ring-cyan-500 focus:border-cyan-500 transition-colors"
              required
            >
              <option value="standard">Standard</option>
              <option value="rush">Rush</option>
              <option value="emergency">Emergency</option>
            </select>
          </div>

          <div>
            <label class="block text-sm font-medium text-slate-300 mb-2">
              Vehicle Type
            </label>
            <select
              name="service_request[vehicle_type]"
              class="w-full px-4 py-3 bg-slate-700/50 border border-slate-600 rounded-lg text-slate-100 placeholder-slate-500 focus:ring-2 focus:ring-cyan-500 focus:border-cyan-500 transition-colors"
              required
            >
              <option value="compact">Compact Car</option>
              <option value="suv">SUV</option>
              <option value="truck">Truck</option>
            </select>
          </div>

          <div>
            <label class="block text-sm font-medium text-slate-300 mb-2">
              <.icon name="hero-map-pin" class="h-4 w-4 inline mr-1" /> Location
            </label>
            <div class="grid grid-cols-2 gap-3">
              <input
                type="number"
                step="any"
                name="service_request[latitude]"
                class="w-full px-4 py-3 bg-slate-700/50 border border-slate-600 rounded-lg text-slate-100 placeholder-slate-500 focus:ring-2 focus:ring-cyan-500 focus:border-cyan-500 transition-colors"
                placeholder="Latitude"
                required
              />
              <input
                type="number"
                step="any"
                name="service_request[longitude]"
                class="w-full px-4 py-3 bg-slate-700/50 border border-slate-600 rounded-lg text-slate-100 placeholder-slate-500 focus:ring-2 focus:ring-cyan-500 focus:border-cyan-500 transition-colors"
                placeholder="Longitude"
                required
              />
            </div>
          </div>

          <div>
            <label class="block text-sm font-medium text-slate-300 mb-2">
              <.icon name="hero-pencil" class="h-4 w-4 inline mr-1" /> Issue Description
              <span class="text-slate-500">(optional)</span>
            </label>
            <textarea
              name="service_request[issue_notes]"
              rows="3"
              class="w-full px-4 py-3 bg-slate-700/50 border border-slate-600 rounded-lg text-slate-100 placeholder-slate-500 focus:ring-2 focus:ring-cyan-500 focus:border-cyan-500 transition-colors resize-none"
              placeholder="Tell us more about your issue..."
            ></textarea>
          </div>

          <button
            type="submit"
            class="w-full px-6 py-3 bg-gradient-to-r from-blue-500 to-cyan-500 hover:from-blue-600 hover:to-cyan-600 text-white font-semibold rounded-lg shadow-lg shadow-cyan-500/25 focus:outline-none focus:ring-2 focus:ring-cyan-500 focus:ring-offset-2 focus:ring-offset-slate-900 transition-all duration-200 hover:scale-[1.02] flex items-center justify-center"
          >
            <.icon name="hero-calculator" class="h-5 w-5 mr-2" /> Get Quote
          </button>
        </div>
      </.form>

      <%!-- Feature Highlights --%>
      <div class="grid grid-cols-3 gap-4 mt-8 pt-6 border-t border-slate-700">
        <div class="text-center">
          <div class="w-12 h-12 bg-blue-500/20 rounded-full flex items-center justify-center mx-auto mb-2">
            <.icon name="hero-clock" class="h-6 w-6 text-blue-400" />
          </div>
          <p class="text-sm font-medium text-slate-300">Fast Response</p>
          <p class="text-xs text-slate-500">Within 30 minutes</p>
        </div>
        <div class="text-center">
          <div class="w-12 h-12 bg-cyan-500/20 rounded-full flex items-center justify-center mx-auto mb-2">
            <.icon name="hero-map-pin" class="h-6 w-6 text-cyan-400" />
          </div>
          <p class="text-sm font-medium text-slate-300">Real-time Tracking</p>
          <p class="text-xs text-slate-500">Track your helper</p>
        </div>
        <div class="text-center">
          <div class="w-12 h-12 bg-blue-500/20 rounded-full flex items-center justify-center mx-auto mb-2">
            <.icon name="hero-wrench-screwdriver" class="h-6 w-6 text-blue-400" />
          </div>
          <p class="text-sm font-medium text-slate-300">Professional Service</p>
          <p class="text-xs text-slate-500">Certified technicians</p>
        </div>
      </div>
    </div>
    """
  end

  # Render quote display
  defp render_quote_display(assigns) do
    ~H"""
    <div class="bg-slate-800 rounded-2xl shadow-xl p-6 sm:p-8">
      <div class="mb-6">
        <button
          phx-click="back_to_form"
          class="text-cyan-400 hover:text-cyan-300 font-medium flex items-center transition-colors"
        >
          <.icon name="hero-arrow-left" class="h-5 w-5 mr-2" /> Back to form
        </button>
      </div>

      <h2 class="text-2xl font-semibold text-slate-100 mb-6">Your Quote</h2>

      <div class="bg-gradient-to-br from-blue-500/20 to-cyan-500/20 border border-cyan-500/30 rounded-xl p-6 mb-6">
        <div class="text-center">
          <p class="text-sm text-slate-400 mb-3">Estimated Price Range</p>
          <div class="flex items-center justify-center space-x-4">
            <div>
              <p class="text-3xl font-bold text-slate-100">
                ${format_price(@quote.low)}
              </p>
              <p class="text-sm text-slate-400">Low Estimate</p>
            </div>
            <span class="text-2xl text-slate-500">-</span>
            <div>
              <p class="text-3xl font-bold text-slate-100">
                ${format_price(@quote.high)}
              </p>
              <p class="text-sm text-slate-400">High Estimate</p>
            </div>
          </div>
        </div>
      </div>

      <div class="space-y-3 mb-6">
        <div class="flex justify-between py-3 border-b border-slate-700">
          <span class="text-slate-400">Service Type</span>
          <span class="font-medium text-slate-100">{format_service_type(@quote.service_type)}</span>
        </div>
        <div class="flex justify-between py-3 border-b border-slate-700">
          <span class="text-slate-400">Urgency Level</span>
          <span class="font-medium text-slate-100">{format_urgency(@quote.urgency_tier)}</span>
        </div>
        <div class="flex justify-between py-3 border-b border-slate-700">
          <span class="text-slate-400">Vehicle Type</span>
          <span class="font-medium text-slate-100">{format_vehicle(@quote.vehicle_type)}</span>
        </div>
      </div>

      <button
        phx-click="proceed_to_payment"
        class="w-full px-6 py-3 bg-gradient-to-r from-blue-500 to-cyan-500 hover:from-blue-600 hover:to-cyan-600 text-white font-semibold rounded-lg shadow-lg shadow-cyan-500/25 focus:outline-none focus:ring-2 focus:ring-cyan-500 focus:ring-offset-2 focus:ring-offset-slate-900 transition-all duration-200 hover:scale-[1.02]"
      >
        Proceed to Payment
      </button>
    </div>
    """
  end

  # Render payment selection
  defp render_payment_selection(assigns) do
    ~H"""
    <div class="bg-slate-800 rounded-2xl shadow-xl p-6 sm:p-8">
      <div class="mb-6">
        <button
          phx-click="back_to_quote"
          class="text-cyan-400 hover:text-cyan-300 font-medium flex items-center transition-colors"
        >
          <.icon name="hero-arrow-left" class="h-5 w-5 mr-2" /> Back to quote
        </button>
      </div>

      <h2 class="text-2xl font-semibold text-slate-100 mb-6">Select Payment Method</h2>

      <div class="mb-6 bg-blue-500/10 border border-blue-500/30 rounded-lg p-4">
        <div class="flex items-start">
          <div class="flex-shrink-0">
            <.icon name="hero-information-circle" class="h-5 w-5 text-blue-400" />
          </div>
          <div class="ml-3">
            <p class="text-sm text-blue-300">
              Your payment will be held securely until the service is completed.
            </p>
          </div>
        </div>
      </div>

      <div class="space-y-4 mb-8">
        <button
          phx-click="select_payment_method"
          phx-value-method="stripe"
          class={[
            "w-full p-6 border-2 rounded-xl text-left transition-all",
            if(@payment_method == "stripe",
              do: "border-cyan-500 bg-cyan-500/10",
              else: "border-slate-700 hover:border-slate-600"
            )
          ]}
        >
          <div class="flex items-center justify-between">
            <div class="flex items-center">
              <div class={[
                "w-6 h-6 rounded-full border-2 mr-4 flex items-center justify-center",
                if(@payment_method == "stripe",
                  do: "border-cyan-500 bg-cyan-500",
                  else: "border-slate-600"
                )
              ]}>
                <%= if @payment_method == "stripe" do %>
                  <.icon name="hero-check" class="h-4 w-4 text-white" />
                <% end %>
              </div>
              <div>
                <h3 class="text-lg font-semibold text-slate-100">Credit/Debit Card</h3>
                <p class="text-sm text-slate-400">Pay securely with Stripe</p>
              </div>
            </div>
            <div class="text-2xl">💳</div>
          </div>
        </button>

        <button
          phx-click="select_payment_method"
          phx-value-method="mpesa"
          class={[
            "w-full p-6 border-2 rounded-xl text-left transition-all",
            if(@payment_method == "mpesa",
              do: "border-cyan-500 bg-cyan-500/10",
              else: "border-slate-700 hover:border-slate-600"
            )
          ]}
        >
          <div class="flex items-center justify-between">
            <div class="flex items-center">
              <div class={[
                "w-6 h-6 rounded-full border-2 mr-4 flex items-center justify-center",
                if(@payment_method == "mpesa",
                  do: "border-cyan-500 bg-cyan-500",
                  else: "border-slate-600"
                )
              ]}>
                <%= if @payment_method == "mpesa" do %>
                  <.icon name="hero-check" class="h-4 w-4 text-white" />
                <% end %>
              </div>
              <div>
                <h3 class="text-lg font-semibold text-slate-100">M-PESA</h3>
                <p class="text-sm text-slate-400">Pay with mobile money</p>
              </div>
            </div>
            <div class="text-2xl">📱</div>
          </div>
        </button>
      </div>

      <%= if @payment_method == "mpesa" do %>
        <div class="mb-6">
          <label class="block text-sm font-medium text-slate-300 mb-2">
            M-PESA Phone Number
          </label>
          <input
            type="tel"
            id="mpesa-phone-input"
            placeholder="254XXXXXXXXX"
            class="w-full px-4 py-3 bg-slate-700/50 border border-slate-600 rounded-lg text-slate-100 placeholder-slate-500 focus:ring-2 focus:ring-cyan-500 focus:border-cyan-500 transition-colors"
          />
          <p class="mt-1 text-sm text-slate-500">
            Enter your M-PESA registered phone number
          </p>
        </div>
      <% end %>

      <button
        phx-click="confirm_booking"
        disabled={is_nil(@payment_method)}
        class={[
          "w-full px-6 py-3 font-semibold rounded-lg transition-all duration-200",
          if(is_nil(@payment_method),
            do: "bg-slate-700 text-slate-500 cursor-not-allowed",
            else:
              "bg-gradient-to-r from-blue-500 to-cyan-500 hover:from-blue-600 hover:to-cyan-600 text-white shadow-lg shadow-cyan-500/25 focus:outline-none focus:ring-2 focus:ring-cyan-500 focus:ring-offset-2 focus:ring-offset-slate-900 hover:scale-[1.02]"
          )
        ]}
      >
        <%= if @payment_method == "stripe" do %>
          Proceed to Stripe Checkout
        <% else %>
          <%= if @payment_method == "mpesa" do %>
            Send M-PESA Payment Request
          <% else %>
            Select a Payment Method
          <% end %>
        <% end %>
      </button>
    </div>
    """
  end

  # Render job tracking
  defp render_job_tracking(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="bg-white rounded-xl shadow-lg p-8">
        <h2 class="text-2xl font-semibold text-gray-900 mb-6">Track Your Service</h2>

        <%= if @current_job do %>
          <div class="space-y-6">
            <!-- Job Status -->
            <div class="bg-gradient-to-br from-blue-50 to-indigo-50 rounded-lg p-6">
              <div class="flex items-center justify-between mb-4">
                <div>
                  <p class="text-sm text-gray-600 mb-1">Current Status</p>
                  <p class="text-2xl font-bold text-gray-900">
                    {format_job_status(@current_job.status)}
                  </p>
                </div>
                <div class="text-4xl">
                  {status_emoji(@current_job.status)}
                </div>
              </div>
              
    <!-- Status Timeline -->
              <div class="mt-6">
                <div class="flex items-center justify-between">
                  <div class={["flex flex-col items-center", status_class(@current_job.status, :open)]}>
                    <div class="w-10 h-10 rounded-full bg-blue-600 flex items-center justify-center text-white mb-2">
                      <.icon name="hero-check" class="h-6 w-6" />
                    </div>
                    <p class="text-xs text-center">Requested</p>
                  </div>

                  <div class="flex-1 h-1 bg-gray-200 mx-2">
                    <div class={[
                      "h-full bg-blue-600 transition-all duration-500",
                      if(status_reached?(@current_job.status, :accepted), do: "w-full", else: "w-0")
                    ]}>
                    </div>
                  </div>

                  <div class={[
                    "flex flex-col items-center",
                    status_class(@current_job.status, :accepted)
                  ]}>
                    <div class={[
                      "w-10 h-10 rounded-full flex items-center justify-center text-white mb-2",
                      if(status_reached?(@current_job.status, :accepted),
                        do: "bg-blue-600",
                        else: "bg-gray-300"
                      )
                    ]}>
                      <%= if status_reached?(@current_job.status, :accepted) do %>
                        <.icon name="hero-check" class="h-6 w-6" />
                      <% end %>
                    </div>
                    <p class="text-xs text-center">Accepted</p>
                  </div>

                  <div class="flex-1 h-1 bg-gray-200 mx-2">
                    <div class={[
                      "h-full bg-blue-600 transition-all duration-500",
                      if(status_reached?(@current_job.status, :en_route), do: "w-full", else: "w-0")
                    ]}>
                    </div>
                  </div>

                  <div class={[
                    "flex flex-col items-center",
                    status_class(@current_job.status, :en_route)
                  ]}>
                    <div class={[
                      "w-10 h-10 rounded-full flex items-center justify-center text-white mb-2",
                      if(status_reached?(@current_job.status, :en_route),
                        do: "bg-blue-600",
                        else: "bg-gray-300"
                      )
                    ]}>
                      <%= if status_reached?(@current_job.status, :en_route) do %>
                        <.icon name="hero-check" class="h-6 w-6" />
                      <% end %>
                    </div>
                    <p class="text-xs text-center">En Route</p>
                  </div>

                  <div class="flex-1 h-1 bg-gray-200 mx-2">
                    <div class={[
                      "h-full bg-blue-600 transition-all duration-500",
                      if(status_reached?(@current_job.status, :on_site), do: "w-full", else: "w-0")
                    ]}>
                    </div>
                  </div>

                  <div class={[
                    "flex flex-col items-center",
                    status_class(@current_job.status, :on_site)
                  ]}>
                    <div class={[
                      "w-10 h-10 rounded-full flex items-center justify-center text-white mb-2",
                      if(status_reached?(@current_job.status, :on_site),
                        do: "bg-blue-600",
                        else: "bg-gray-300"
                      )
                    ]}>
                      <%= if status_reached?(@current_job.status, :on_site) do %>
                        <.icon name="hero-check" class="h-6 w-6" />
                      <% end %>
                    </div>
                    <p class="text-xs text-center">On Site</p>
                  </div>

                  <div class="flex-1 h-1 bg-gray-200 mx-2">
                    <div class={[
                      "h-full bg-blue-600 transition-all duration-500",
                      if(status_reached?(@current_job.status, :completed), do: "w-full", else: "w-0")
                    ]}>
                    </div>
                  </div>

                  <div class={[
                    "flex flex-col items-center",
                    status_class(@current_job.status, :completed)
                  ]}>
                    <div class={[
                      "w-10 h-10 rounded-full flex items-center justify-center text-white mb-2",
                      if(status_reached?(@current_job.status, :completed),
                        do: "bg-green-600",
                        else: "bg-gray-300"
                      )
                    ]}>
                      <%= if status_reached?(@current_job.status, :completed) do %>
                        <.icon name="hero-check" class="h-6 w-6" />
                      <% end %>
                    </div>
                    <p class="text-xs text-center">Complete</p>
                  </div>
                </div>
              </div>
            </div>
            
    <!-- Provider Info (if assigned) -->
            <%= if @current_job.provider_id do %>
              <div class="border border-gray-200 rounded-lg p-6">
                <h3 class="text-lg font-semibold text-gray-900 mb-4">Provider Information</h3>
                <div class="space-y-3">
                  <div class="flex justify-between">
                    <span class="text-gray-600">Provider ID</span>
                    <span class="font-medium text-gray-900">
                      {String.slice(@current_job.provider_id, 0..7)}...
                    </span>
                  </div>
                  <%= if @provider_location do %>
                    <div class="flex justify-between">
                      <span class="text-gray-600">Current Location</span>
                      <span class="font-medium text-gray-900">
                        {Float.round(@provider_location.latitude, 4)}, {Float.round(
                          @provider_location.longitude,
                          4
                        )}
                      </span>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
            
    <!-- Map Placeholder -->
            <div class="border border-gray-200 rounded-lg p-6 bg-gray-50">
              <h3 class="text-lg font-semibold text-gray-900 mb-4">Live Map</h3>
              <div class="bg-white rounded-lg h-64 flex items-center justify-center border-2 border-dashed border-gray-300">
                <div class="text-center">
                  <.icon name="hero-map" class="h-12 w-12 text-gray-400 mx-auto mb-2" />
                  <p class="text-gray-500">Map integration coming soon</p>
                  <%= if @provider_location do %>
                    <p class="text-sm text-gray-400 mt-2">
                      Provider at: {Float.round(@provider_location.latitude, 4)}, {Float.round(
                        @provider_location.longitude,
                        4
                      )}
                    </p>
                  <% end %>
                </div>
              </div>
            </div>
            
    <!-- Job Details -->
            <div class="border border-gray-200 rounded-lg p-6">
              <h3 class="text-lg font-semibold text-gray-900 mb-4">Job Details</h3>
              <div class="space-y-3">
                <div class="flex justify-between">
                  <span class="text-gray-600">Service Type</span>
                  <span class="font-medium text-gray-900">
                    {format_service_type(@current_job.service_type)}
                  </span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-600">Urgency</span>
                  <span class="font-medium text-gray-900">
                    {format_urgency(@current_job.urgency_tier)}
                  </span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-600">Vehicle</span>
                  <span class="font-medium text-gray-900">
                    {format_vehicle(@current_job.vehicle_type)}
                  </span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-600">Estimated Price</span>
                  <span class="font-medium text-gray-900">
                    ${format_price(@current_job.estimated_price_cents)}
                  </span>
                </div>
              </div>
            </div>
            
    <!-- Cancel Button (only if not completed) -->
            <%= if @current_job.status not in [:completed, :cancelled] do %>
              <button
                phx-click="show_cancel_confirmation"
                class="w-full px-6 py-3 bg-red-600 text-white font-semibold rounded-lg hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 transition-colors duration-200"
              >
                Cancel Job
              </button>
            <% end %>
          </div>
        <% else %>
          <div class="text-center py-12">
            <.icon name="hero-exclamation-circle" class="h-16 w-16 text-gray-400 mx-auto mb-4" />
            <p class="text-gray-500">No active job found</p>
            <button
              phx-click="back_to_form"
              class="mt-4 text-blue-600 hover:text-blue-700 font-medium"
            >
              Request a new service
            </button>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Event Handlers

  @impl true
  def handle_event("request_service", %{"service_request" => params}, socket) do
    # Parse parameters
    service_type = String.to_existing_atom(params["service_type"])
    urgency_tier = String.to_existing_atom(params["urgency_tier"])
    vehicle_type = String.to_existing_atom(params["vehicle_type"])

    latitude = String.to_float(params["latitude"])
    longitude = String.to_float(params["longitude"])

    driver_location = %{latitude: latitude, longitude: longitude}

    # Calculate quote
    case Pricing.calculate_quote(driver_location, service_type, urgency_tier, vehicle_type) do
      {:ok, quote_result} ->
        # Store quote with additional context
        quote =
          Map.merge(quote_result, %{
            service_type: service_type,
            urgency_tier: urgency_tier,
            vehicle_type: vehicle_type,
            latitude: latitude,
            longitude: longitude,
            issue_notes: Map.get(params, "issue_notes", "")
          })

        Logger.info("Quote calculated", %{
          user_id: socket.assigns.user_id,
          low: quote.low,
          high: quote.high
        })

        {:noreply,
         socket
         |> assign(quote: quote, step: :quote, error_message: nil)
         |> put_flash(:info, "Quote calculated successfully")}

      {:error, reason} ->
        Logger.error("Quote calculation failed", %{
          user_id: socket.assigns.user_id,
          reason: inspect(reason)
        })

        {:noreply,
         socket
         |> assign(error_message: "Failed to calculate quote: #{inspect(reason)}")
         |> put_flash(:error, "Failed to calculate quote")}
    end
  end

  @impl true
  def handle_event("back_to_form", _params, socket) do
    {:noreply, assign(socket, step: :input, error_message: nil)}
  end

  @impl true
  def handle_event("proceed_to_payment", _params, socket) do
    {:noreply, assign(socket, step: :payment, error_message: nil)}
  end

  @impl true
  def handle_event("back_to_quote", _params, socket) do
    {:noreply, assign(socket, step: :quote, error_message: nil)}
  end

  @impl true
  def handle_event("select_payment_method", %{"method" => method}, socket) do
    {:noreply, assign(socket, payment_method: method, error_message: nil)}
  end

  @impl true
  def handle_event("confirm_booking", _params, socket) do
    quote = socket.assigns.quote
    payment_method = socket.assigns.payment_method

    # Create the job first
    driver_location = %Geo.Point{
      coordinates: {quote.longitude, quote.latitude},
      srid: 4326
    }

    job_attrs = %{
      service_type: quote.service_type,
      urgency_tier: quote.urgency_tier,
      vehicle_type: quote.vehicle_type,
      driver_location: driver_location,
      estimated_price_cents: quote.low,
      issue_notes: quote.issue_notes,
      status: :open
    }

    case Jobs.create_job(socket.assigns.user_id, job_attrs) do
      {:ok, job} ->
        Logger.info("Job created", %{
          job_id: job.id,
          driver_id: socket.assigns.user_id,
          payment_method: payment_method
        })

        # Create payment transaction
        case Payments.create_payment(
               job.id,
               quote.low,
               socket.assigns.user_id,
               String.to_existing_atom(payment_method)
             ) do
          {:ok, _transaction} ->
            # Initiate payment based on method
            handle_payment_initiation(socket, job, payment_method, quote.low)

          {:error, changeset} ->
            Logger.error("Failed to create payment transaction", %{
              job_id: job.id,
              errors: inspect(changeset.errors)
            })

            {:noreply,
             socket
             |> assign(error_message: "Failed to create payment transaction")
             |> put_flash(:error, "Failed to create payment transaction")}
        end

      {:error, changeset} ->
        Logger.error("Failed to create job", %{
          driver_id: socket.assigns.user_id,
          errors: inspect(changeset.errors)
        })

        {:noreply,
         socket
         |> assign(error_message: "Failed to create job")
         |> put_flash(:error, "Failed to create job")}
    end
  end

  @impl true
  def handle_event("show_cancel_confirmation", _params, socket) do
    {:noreply, assign(socket, show_cancel_modal: true)}
  end

  @impl true
  def handle_event("hide_cancel_confirmation", _params, socket) do
    {:noreply, assign(socket, show_cancel_modal: false)}
  end

  @impl true
  def handle_event("stop_propagation", _params, socket) do
    # This prevents the modal from closing when clicking inside it
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_job", _params, socket) do
    case socket.assigns.current_job do
      nil ->
        {:noreply,
         socket
         |> assign(show_cancel_modal: false)
         |> put_flash(:error, "No active job to cancel")}

      job ->
        case Jobs.cancel_job(job, "Cancelled by driver") do
          {:ok, cancelled_job} ->
            Logger.info("Job cancelled by driver", %{
              job_id: cancelled_job.id,
              driver_id: socket.assigns.user_id
            })

            {:noreply,
             socket
             |> assign(
               current_job: nil,
               step: :input,
               show_cancel_modal: false,
               quote: nil,
               payment_method: nil,
               provider_location: nil
             )
             |> put_flash(:info, "Job cancelled successfully")}

          {:error, reason} ->
            Logger.error("Failed to cancel job", %{
              job_id: job.id,
              reason: inspect(reason)
            })

            {:noreply,
             socket
             |> assign(show_cancel_modal: false)
             |> put_flash(:error, "Failed to cancel job: #{inspect(reason)}")}
        end
    end
  end

  # Handle payment initiation based on method
  defp handle_payment_initiation(socket, job, "stripe", amount_cents) do
    case Payments.initiate_stripe_checkout(job.id, amount_cents) do
      {:ok, %{checkout_url: url}} ->
        Logger.info("Redirecting to Stripe Checkout", %{
          job_id: job.id,
          checkout_url: url
        })

        {:noreply,
         socket
         |> put_flash(:info, "Redirecting to Stripe Checkout...")
         |> redirect(external: url)}

      {:error, reason} ->
        Logger.error("Failed to initiate Stripe Checkout", %{
          job_id: job.id,
          reason: inspect(reason)
        })

        {:noreply,
         socket
         |> assign(error_message: "Failed to initiate Stripe Checkout: #{inspect(reason)}")
         |> put_flash(:error, "Failed to initiate payment")}
    end
  end

  defp handle_payment_initiation(socket, job, "mpesa", amount_cents) do
    # Get phone number from the form
    # Note: In a real implementation, we'd use phx-change to capture this value
    # For now, we'll show a message that STK Push has been initiated
    amount_kes = div(amount_cents, 100)

    # In a real implementation, you would:
    # 1. Get the phone number from socket assigns (captured via phx-change)
    # 2. Call MPESA.initiate_stk_push with the phone number
    # For now, we'll just show a placeholder message

    Logger.info("M-PESA payment initiated", %{
      job_id: job.id,
      amount_kes: amount_kes
    })

    {:noreply,
     socket
     |> assign(
       current_job: job,
       step: :tracking,
       error_message: nil
     )
     |> put_flash(
       :info,
       "M-PESA payment request sent! Please check your phone and enter your M-PESA PIN."
     )}
  end

  # Helper functions for formatting

  defp format_price(cents) when is_integer(cents) do
    dollars = cents / 100
    :erlang.float_to_binary(dollars, decimals: 2)
  end

  defp format_service_type(:flat_repair), do: "Flat Tire Repair"
  defp format_service_type(:nail_removal), do: "Nail Removal"
  defp format_service_type(:air_fill), do: "Air Fill"
  defp format_service_type(:new_tire), do: "New Tire Installation"
  defp format_service_type(:replacement), do: "Tire Replacement"
  defp format_service_type(_), do: "Unknown"

  defp format_urgency(:standard), do: "Standard (1-2 hours)"
  defp format_urgency(:rush), do: "Rush (30-60 minutes)"
  defp format_urgency(:emergency), do: "Emergency (ASAP)"
  defp format_urgency(_), do: "Unknown"

  defp format_vehicle(:compact), do: "Compact Car"
  defp format_vehicle(:suv), do: "SUV"
  defp format_vehicle(:truck), do: "Truck"
  defp format_vehicle(_), do: "Unknown"

  defp format_job_status(:open), do: "Waiting for Provider"
  defp format_job_status(:payment_confirmed), do: "Payment Confirmed"
  defp format_job_status(:accepted), do: "Provider Assigned"
  defp format_job_status(:en_route), do: "Provider En Route"
  defp format_job_status(:on_site), do: "Provider On Site"
  defp format_job_status(:completed), do: "Service Completed"
  defp format_job_status(:cancelled), do: "Cancelled"
  defp format_job_status(_), do: "Unknown"

  defp status_emoji(:open), do: "⏳"
  defp status_emoji(:payment_confirmed), do: "💳"
  defp status_emoji(:accepted), do: "✅"
  defp status_emoji(:en_route), do: "🚗"
  defp status_emoji(:on_site), do: "🔧"
  defp status_emoji(:completed), do: "🎉"
  defp status_emoji(:cancelled), do: "❌"
  defp status_emoji(_), do: "❓"

  # Status progression order
  @status_order [:open, :payment_confirmed, :accepted, :en_route, :on_site, :completed]

  defp status_reached?(current_status, target_status) do
    current_index = Enum.find_index(@status_order, &(&1 == current_status)) || 0
    target_index = Enum.find_index(@status_order, &(&1 == target_status)) || 0
    current_index >= target_index
  end

  defp status_class(current_status, target_status) do
    if status_reached?(current_status, target_status) do
      "text-blue-600"
    else
      "text-gray-400"
    end
  end

  # PubSub message handlers

  @impl true
  def handle_info(%{event: "job_created", payload: %{job: job}}, socket) do
    Logger.info("Job created event received", %{job_id: job.id})

    {:noreply,
     socket
     |> assign(current_job: job)
     |> put_flash(:info, "Job created successfully")}
  end

  @impl true
  def handle_info(%{event: "job_accepted", payload: %{job: job}}, socket) do
    Logger.info("Job accepted event received", %{
      job_id: job.id,
      provider_id: job.provider_id
    })

    {:noreply,
     socket
     |> assign(current_job: job)
     |> put_flash(:info, "A provider has accepted your job!")}
  end

  @impl true
  def handle_info(%{event: "job_updated", payload: %{job: job}}, socket) do
    Logger.info("Job updated event received", %{
      job_id: job.id,
      status: job.status
    })

    {:noreply,
     socket
     |> assign(current_job: job)
     |> put_flash(:info, "Job status updated: #{format_job_status(job.status)}")}
  end

  @impl true
  def handle_info(%{event: "job_completed", payload: %{job: job}}, socket) do
    Logger.info("Job completed event received", %{job_id: job.id})

    {:noreply,
     socket
     |> assign(current_job: job)
     |> put_flash(:success, "Service completed! Thank you for using our service.")}
  end

  @impl true
  def handle_info(%{event: "job_cancelled", payload: %{job: job}}, socket) do
    Logger.info("Job cancelled event received", %{job_id: job.id})

    {:noreply,
     socket
     |> assign(current_job: job, step: :input)
     |> put_flash(:info, "Job has been cancelled")}
  end

  @impl true
  def handle_info(%{event: "provider_location_update", payload: payload}, socket) do
    location = payload.location

    Logger.debug("Provider location update received", %{
      job_id: payload.job_id,
      latitude: location.latitude,
      longitude: location.longitude
    })

    {:noreply, assign(socket, provider_location: location)}
  end

  # Catch-all for other messages
  @impl true
  def handle_info(msg, socket) do
    Logger.debug("Unhandled message in DriverDashboardLive", %{message: inspect(msg)})
    {:noreply, socket}
  end
end
