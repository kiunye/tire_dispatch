defmodule TireDispatchWeb.ProviderDashboardLive do
  @moduledoc """
  LiveView for the provider dashboard.

  Handles job discovery, acceptance, state transitions, photo uploads,
  and earnings tracking for tire service providers.
  """
  use TireDispatchWeb, :live_view

  import Ecto.Query, warn: false

  alias TireDispatch.{Jobs, Photos, Providers, Repo}

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    # Check if user is authenticated
    case Map.get(socket.assigns, :current_scope) do
      nil ->
        {:ok, redirect(socket, to: ~p"/users/log-in")}

      current_scope ->
        user_id = current_scope.user.id

        # Get provider profile
        case Providers.get_provider_by_user_id(user_id) do
          {:ok, provider} ->
            # Subscribe to provider-specific job updates
            Phoenix.PubSub.subscribe(TireDispatch.PubSub, "provider:#{provider.id}:jobs")

            # Query open jobs within service radius
            available_jobs =
              Jobs.open_jobs_within_radius(
                provider.latitude,
                provider.longitude,
                provider.service_radius_km
              )

            # Query active job (if any)
            active_job = get_active_job(provider.id)

            # Calculate earnings
            earnings = calculate_earnings(provider.id)

            socket =
              socket
              |> assign(
                user_id: user_id,
                provider_id: provider.id,
                provider: provider,
                available_jobs: available_jobs,
                active_job: active_job,
                earnings: earnings,
                error_message: nil,
                before_photo_url: nil,
                after_photo_url: nil,
                uploading: false,
                show_payout_form: false,
                payout_form: to_form(%{})
              )
              |> allow_upload(:before_photo,
                accept: ~w(.jpg .jpeg .png),
                max_entries: 1,
                max_file_size: 5_000_000
              )
              |> allow_upload(:after_photo,
                accept: ~w(.jpg .jpeg .png),
                max_entries: 1,
                max_file_size: 5_000_000
              )

            {:ok, socket}

          {:error, :not_found} ->
            {:ok,
             socket
             |> put_flash(:error, "Provider profile not found. Please contact support.")
             |> redirect(to: ~p"/")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="min-h-screen bg-gradient-to-br from-emerald-50 via-teal-50 to-cyan-50">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          <%!-- Header with modern styling --%>
          <div class="mb-10">
            <div class="flex items-center justify-between">
              <div>
                <h1 class="text-5xl font-extrabold bg-gradient-to-r from-emerald-600 to-teal-600 bg-clip-text text-transparent">
                  Provider Dashboard
                </h1>
                <p class="mt-3 text-lg text-gray-600 font-medium">
                  Manage your jobs and track your earnings
                </p>
              </div>
              <div class="hidden md:flex items-center space-x-3">
                <div class="px-4 py-2 bg-white rounded-full shadow-sm border border-gray-200">
                  <span class="text-sm font-semibold text-gray-700">
                    {@provider.service_radius_km} km radius
                  </span>
                </div>
                <div class="px-4 py-2 bg-gradient-to-r from-emerald-500 to-teal-500 rounded-full shadow-md">
                  <span class="text-sm font-semibold text-white">
                    ⭐ {Float.round(@provider.rating || 0.0, 1)}
                  </span>
                </div>
              </div>
            </div>
          </div>

          <%= if @error_message do %>
            <div class="mb-6 bg-red-50 border-l-4 border-red-500 rounded-r-xl p-4 shadow-sm animate-pulse">
              <div class="flex">
                <div class="flex-shrink-0">
                  <.icon name="hero-x-circle" class="h-6 w-6 text-red-500" />
                </div>
                <div class="ml-3">
                  <p class="text-sm font-medium text-red-800">{@error_message}</p>
                </div>
              </div>
            </div>
          <% end %>

          <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
            <%!-- Left Column: Available Jobs and Active Job --%>
            <div class="lg:col-span-2 space-y-6">
              <%= if @active_job do %>
                {render_active_job(assigns)}
              <% else %>
                {render_available_jobs(assigns)}
              <% end %>
            </div>
            <%!-- Right Column: Earnings Dashboard --%>
            <div class="lg:col-span-1">
              {render_earnings_dashboard(assigns)}
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Render available jobs feed
  defp render_available_jobs(assigns) do
    ~H"""
    <div class="bg-white/80 backdrop-blur-sm rounded-2xl shadow-xl border border-gray-100 p-8">
      <div class="flex items-center justify-between mb-6">
        <h2 class="text-3xl font-bold text-gray-900">Available Jobs</h2>
        <span class="px-3 py-1 bg-emerald-100 text-emerald-700 rounded-full text-sm font-semibold">
          {length(@available_jobs)} nearby
        </span>
      </div>

      <%= if Enum.empty?(@available_jobs) do %>
        <div class="text-center py-16">
          <div class="inline-flex items-center justify-center w-20 h-20 bg-gradient-to-br from-gray-100 to-gray-200 rounded-full mb-4">
            <.icon name="hero-inbox" class="h-10 w-10 text-gray-400" />
          </div>
          <p class="text-gray-600 text-xl font-semibold">No jobs available in your area</p>
          <p class="text-gray-400 text-sm mt-2">
            New jobs will appear here automatically
          </p>
        </div>
      <% else %>
        <div class="space-y-4">
          <%= for job <- @available_jobs do %>
            <div class="group relative bg-gradient-to-br from-white to-gray-50 border-2 border-gray-200 rounded-2xl p-6 hover:border-emerald-400 hover:shadow-lg transition-all duration-300 transform hover:-translate-y-1">
              <%!-- Urgency indicator --%>
              <div class="absolute top-4 right-4">
                <span class={[
                  "px-3 py-1 rounded-full text-xs font-bold uppercase tracking-wide",
                  urgency_badge_class(job.urgency_tier)
                ]}>
                  {format_urgency(job.urgency_tier)}
                </span>
              </div>

              <div class="flex justify-between items-start mb-4 pr-24">
                <div>
                  <h3 class="text-xl font-bold text-gray-900 mb-2">
                    {format_service_type(job.service_type)}
                  </h3>
                  <div class="flex items-center space-x-3 text-sm text-gray-600">
                    <span class="flex items-center">
                      <.icon name="hero-truck" class="h-4 w-4 mr-1" />
                      {format_vehicle(job.vehicle_type)}
                    </span>
                    <span class="flex items-center">
                      <.icon name="hero-map-pin" class="h-4 w-4 mr-1" />
                      {format_distance(job, @provider)}
                    </span>
                  </div>
                </div>
              </div>

              <div class="mb-4">
                <div class="inline-flex items-baseline">
                  <span class="text-4xl font-extrabold bg-gradient-to-r from-emerald-600 to-teal-600 bg-clip-text text-transparent">
                    ${format_price(job.estimated_price_cents)}
                  </span>
                  <span class="ml-2 text-sm text-gray-500 font-medium">estimated</span>
                </div>
              </div>

              <%= if job.issue_notes && job.issue_notes != "" do %>
                <div class="mb-4 p-4 bg-amber-50 border border-amber-200 rounded-xl">
                  <p class="text-sm text-amber-900">
                    <span class="font-bold">Issue:</span>
                    {job.issue_notes}
                  </p>
                </div>
              <% end %>

              <div class="flex items-center justify-end space-x-3 pt-4 border-t border-gray-200">
                <button
                  phx-click="decline_job"
                  phx-value-job-id={job.id}
                  class="px-5 py-2.5 bg-gray-100 text-gray-700 font-semibold rounded-xl hover:bg-gray-200 transition-all duration-200 transform hover:scale-105"
                >
                  Decline
                </button>
                <button
                  phx-click="accept_job"
                  phx-value-job-id={job.id}
                  class="px-6 py-2.5 bg-gradient-to-r from-emerald-500 to-teal-500 text-white font-bold rounded-xl hover:from-emerald-600 hover:to-teal-600 shadow-md hover:shadow-lg transition-all duration-200 transform hover:scale-105"
                >
                  Accept Job →
                </button>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # Render active job management
  defp render_active_job(assigns) do
    ~H"""
    <div class="bg-white/80 backdrop-blur-sm rounded-2xl shadow-xl border border-gray-100 p-8">
      <div class="flex items-center justify-between mb-6">
        <h2 class="text-3xl font-bold text-gray-900">Active Job</h2>
        <span class="px-3 py-1 bg-emerald-100 text-emerald-700 rounded-full text-sm font-semibold animate-pulse">
          ● In Progress
        </span>
      </div>

      <div class="space-y-6">
        <%!-- Job Status with modern design --%>
        <div class="relative overflow-hidden bg-gradient-to-br from-emerald-500 to-teal-600 rounded-2xl p-6 shadow-lg">
          <div class="absolute top-0 right-0 w-32 h-32 bg-white/10 rounded-full -mr-16 -mt-16"></div>
          <div class="absolute bottom-0 left-0 w-24 h-24 bg-white/10 rounded-full -ml-12 -mb-12">
          </div>
          <div class="relative flex items-center justify-between">
            <div>
              <p class="text-sm text-emerald-100 mb-1 font-medium">Current Status</p>
              <p class="text-3xl font-extrabold text-white">
                {format_job_status(@active_job.status)}
              </p>
            </div>
            <div class="text-6xl">
              {status_emoji(@active_job.status)}
            </div>
          </div>
        </div>
        <%!-- Job Details with modern card design --%>
        <div class="bg-gradient-to-br from-white to-gray-50 border-2 border-gray-200 rounded-2xl p-6">
          <h3 class="text-xl font-bold text-gray-900 mb-5 flex items-center">
            <.icon name="hero-document-text" class="h-5 w-5 mr-2 text-emerald-600" /> Job Details
          </h3>
          <div class="space-y-4">
            <div class="flex justify-between items-center p-3 bg-white rounded-xl">
              <span class="text-gray-600 font-medium">Service Type</span>
              <span class="font-bold text-gray-900">
                {format_service_type(@active_job.service_type)}
              </span>
            </div>
            <div class="flex justify-between items-center p-3 bg-white rounded-xl">
              <span class="text-gray-600 font-medium">Urgency</span>
              <span class={[
                "px-3 py-1 rounded-full text-xs font-bold",
                urgency_badge_class(@active_job.urgency_tier)
              ]}>
                {format_urgency(@active_job.urgency_tier)}
              </span>
            </div>
            <div class="flex justify-between items-center p-3 bg-white rounded-xl">
              <span class="text-gray-600 font-medium">Vehicle</span>
              <span class="font-bold text-gray-900">
                {format_vehicle(@active_job.vehicle_type)}
              </span>
            </div>
            <div class="flex justify-between items-center p-3 bg-gradient-to-r from-emerald-50 to-teal-50 rounded-xl border-2 border-emerald-200">
              <span class="text-gray-700 font-bold">Estimated Price</span>
              <span class="text-2xl font-extrabold bg-gradient-to-r from-emerald-600 to-teal-600 bg-clip-text text-transparent">
                ${format_price(@active_job.estimated_price_cents)}
              </span>
            </div>
          </div>
        </div>
        <%!-- Action Buttons based on status with modern styling --%>
        <div class="space-y-3">
          <%= cond do %>
            <% @active_job.status == :accepted -> %>
              <button
                phx-click="start_travel"
                class="w-full px-6 py-5 bg-gradient-to-r from-emerald-500 to-teal-500 text-white font-bold text-lg rounded-2xl hover:from-emerald-600 hover:to-teal-600 shadow-lg hover:shadow-xl transition-all duration-200 transform hover:scale-[1.02] flex items-center justify-center"
              >
                <.icon name="hero-arrow-right-circle" class="h-6 w-6 mr-2" /> Start Travel to Job Site
              </button>
            <% @active_job.status == :en_route -> %>
              <button
                phx-click="mark_on_site"
                class="w-full px-6 py-5 bg-gradient-to-r from-emerald-500 to-teal-500 text-white font-bold text-lg rounded-2xl hover:from-emerald-600 hover:to-teal-600 shadow-lg hover:shadow-xl transition-all duration-200 transform hover:scale-[1.02] flex items-center justify-center"
              >
                <.icon name="hero-map-pin" class="h-6 w-6 mr-2" /> Mark as On Site
              </button>
            <% @active_job.status == :on_site -> %>
              <div class="space-y-5">
                <div class="text-center p-4 bg-gradient-to-r from-blue-50 to-cyan-50 border-2 border-blue-200 rounded-2xl">
                  <p class="text-sm text-blue-900 font-bold">
                    📸 Upload before and after photos to complete the job
                  </p>
                </div>
                <%!-- Before Photo Upload with modern design --%>
                <div class="bg-gradient-to-br from-white to-gray-50 border-2 border-gray-200 rounded-2xl p-5">
                  <label class="block text-base font-bold text-gray-900 mb-3 flex items-center">
                    <.icon name="hero-camera" class="h-5 w-5 mr-2 text-blue-600" /> Before Photo
                  </label>
                  <%= if @before_photo_url do %>
                    <div class="relative group">
                      <img
                        src={@before_photo_url}
                        alt="Before photo"
                        class="w-full h-56 object-cover rounded-xl shadow-md"
                      />
                      <div class="absolute top-3 right-3 bg-emerald-500 text-white px-3 py-1.5 rounded-full text-sm font-bold shadow-lg flex items-center">
                        <.icon name="hero-check-circle" class="h-4 w-4 mr-1" /> Uploaded
                      </div>
                    </div>
                  <% else %>
                    <form phx-change="validate_before_photo" phx-submit="upload_before_photo">
                      <.live_file_input upload={@uploads.before_photo} class="hidden" />
                      <label
                        for={@uploads.before_photo.ref}
                        class="flex flex-col items-center justify-center w-full h-40 border-3 border-blue-300 border-dashed rounded-xl cursor-pointer bg-gradient-to-br from-blue-50 to-cyan-50 hover:from-blue-100 hover:to-cyan-100 transition-all duration-200 group"
                      >
                        <div class="flex flex-col items-center justify-center pt-5 pb-6">
                          <div class="p-3 bg-blue-100 rounded-full mb-3 group-hover:bg-blue-200 transition-colors">
                            <.icon name="hero-camera" class="w-8 h-8 text-blue-600" />
                          </div>
                          <p class="text-sm text-gray-700 font-semibold">
                            <span class="text-blue-600">Click to upload</span> or drag and drop
                          </p>
                          <p class="text-xs text-gray-500 mt-1">PNG or JPG (max 5MB)</p>
                        </div>
                      </label>
                    </form>
                    <%= for entry <- @uploads.before_photo.entries do %>
                      <div class="mt-3 flex items-center justify-between p-3 bg-blue-50 border border-blue-200 rounded-xl">
                        <span class="text-sm text-gray-800 font-medium">{entry.client_name}</span>
                        <button
                          type="button"
                          phx-click="cancel_upload"
                          phx-value-ref={entry.ref}
                          phx-value-type="before_photo"
                          class="text-red-600 hover:text-red-800 transition-colors"
                        >
                          <.icon name="hero-x-mark" class="w-5 h-5" />
                        </button>
                      </div>
                      <button
                        type="button"
                        phx-click="upload_before_photo"
                        class="mt-3 w-full px-4 py-3 bg-gradient-to-r from-blue-500 to-cyan-500 text-white font-bold rounded-xl hover:from-blue-600 hover:to-cyan-600 shadow-md hover:shadow-lg transition-all duration-200 transform hover:scale-[1.02]"
                      >
                        Upload Before Photo
                      </button>
                    <% end %>
                  <% end %>
                </div>
                <%!-- After Photo Upload with modern design --%>
                <div class="bg-gradient-to-br from-white to-gray-50 border-2 border-gray-200 rounded-2xl p-5">
                  <label class="block text-base font-bold text-gray-900 mb-3 flex items-center">
                    <.icon name="hero-camera" class="h-5 w-5 mr-2 text-emerald-600" /> After Photo
                  </label>
                  <%= if @after_photo_url do %>
                    <div class="relative group">
                      <img
                        src={@after_photo_url}
                        alt="After photo"
                        class="w-full h-56 object-cover rounded-xl shadow-md"
                      />
                      <div class="absolute top-3 right-3 bg-emerald-500 text-white px-3 py-1.5 rounded-full text-sm font-bold shadow-lg flex items-center">
                        <.icon name="hero-check-circle" class="h-4 w-4 mr-1" /> Uploaded
                      </div>
                    </div>
                  <% else %>
                    <form phx-change="validate_after_photo" phx-submit="upload_after_photo">
                      <.live_file_input upload={@uploads.after_photo} class="hidden" />
                      <label
                        for={@uploads.after_photo.ref}
                        class="flex flex-col items-center justify-center w-full h-40 border-3 border-emerald-300 border-dashed rounded-xl cursor-pointer bg-gradient-to-br from-emerald-50 to-teal-50 hover:from-emerald-100 hover:to-teal-100 transition-all duration-200 group"
                      >
                        <div class="flex flex-col items-center justify-center pt-5 pb-6">
                          <div class="p-3 bg-emerald-100 rounded-full mb-3 group-hover:bg-emerald-200 transition-colors">
                            <.icon name="hero-camera" class="w-8 h-8 text-emerald-600" />
                          </div>
                          <p class="text-sm text-gray-700 font-semibold">
                            <span class="text-emerald-600">Click to upload</span> or drag and drop
                          </p>
                          <p class="text-xs text-gray-500 mt-1">PNG or JPG (max 5MB)</p>
                        </div>
                      </label>
                    </form>
                    <%= for entry <- @uploads.after_photo.entries do %>
                      <div class="mt-3 flex items-center justify-between p-3 bg-emerald-50 border border-emerald-200 rounded-xl">
                        <span class="text-sm text-gray-800 font-medium">{entry.client_name}</span>
                        <button
                          type="button"
                          phx-click="cancel_upload"
                          phx-value-ref={entry.ref}
                          phx-value-type="after_photo"
                          class="text-red-600 hover:text-red-800 transition-colors"
                        >
                          <.icon name="hero-x-mark" class="w-5 h-5" />
                        </button>
                      </div>
                      <button
                        type="button"
                        phx-click="upload_after_photo"
                        class="mt-3 w-full px-4 py-3 bg-gradient-to-r from-emerald-500 to-teal-500 text-white font-bold rounded-xl hover:from-emerald-600 hover:to-teal-600 shadow-md hover:shadow-lg transition-all duration-200 transform hover:scale-[1.02]"
                      >
                        Upload After Photo
                      </button>
                    <% end %>
                  <% end %>
                </div>
                <%!-- Complete Job Button with modern styling --%>
                <%= if @before_photo_url && @after_photo_url do %>
                  <button
                    phx-click="complete_job_with_photos"
                    class="w-full px-6 py-5 bg-gradient-to-r from-emerald-500 via-teal-500 to-cyan-500 text-white font-extrabold text-lg rounded-2xl hover:from-emerald-600 hover:via-teal-600 hover:to-cyan-600 shadow-xl hover:shadow-2xl transition-all duration-200 transform hover:scale-[1.02] flex items-center justify-center"
                    disabled={@uploading}
                  >
                    <%= if @uploading do %>
                      <div class="flex items-center">
                        <svg
                          class="animate-spin h-5 w-5 mr-3"
                          xmlns="http://www.w3.org/2000/svg"
                          fill="none"
                          viewBox="0 0 24 24"
                        >
                          <circle
                            class="opacity-25"
                            cx="12"
                            cy="12"
                            r="10"
                            stroke="currentColor"
                            stroke-width="4"
                          >
                          </circle>
                          <path
                            class="opacity-75"
                            fill="currentColor"
                            d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                          >
                          </path>
                        </svg>
                        Processing...
                      </div>
                    <% else %>
                      <.icon name="hero-check-badge" class="h-6 w-6 mr-2" /> Complete Job
                    <% end %>
                  </button>
                <% else %>
                  <div class="text-center p-5 bg-gradient-to-r from-amber-50 to-yellow-50 border-2 border-amber-300 rounded-2xl">
                    <.icon
                      name="hero-exclamation-triangle"
                      class="h-6 w-6 text-amber-600 mx-auto mb-2"
                    />
                    <p class="text-sm text-amber-900 font-bold">
                      Please upload both before and after photos to complete the job
                    </p>
                  </div>
                <% end %>
              </div>
            <% true -> %>
              <div class="text-center py-4">
                <p class="text-gray-500">Job in progress...</p>
              </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Render earnings dashboard
  defp render_earnings_dashboard(assigns) do
    ~H"""
    <div class="bg-white/80 backdrop-blur-sm rounded-2xl shadow-xl border border-gray-100 p-8 sticky top-8">
      <h2 class="text-3xl font-bold text-gray-900 mb-6 flex items-center">
        <.icon name="hero-currency-dollar" class="h-7 w-7 mr-2 text-emerald-600" /> Earnings
      </h2>

      <div class="space-y-5">
        <%!-- Total Earnings with stunning gradient --%>
        <div class="relative overflow-hidden bg-gradient-to-br from-emerald-500 via-teal-500 to-cyan-500 rounded-2xl p-6 shadow-lg">
          <div class="absolute top-0 right-0 w-32 h-32 bg-white/10 rounded-full -mr-16 -mt-16"></div>
          <div class="absolute bottom-0 left-0 w-24 h-24 bg-white/10 rounded-full -ml-12 -mb-12">
          </div>
          <div class="relative">
            <p class="text-sm text-emerald-100 mb-2 font-semibold">Total Earnings</p>
            <p class="text-4xl font-extrabold text-white mb-1">
              ${format_price(@earnings.total_cents)}
            </p>
            <p class="text-xs text-emerald-100">All time</p>
          </div>
        </div>
        <%!-- Pending Earnings --%>
        <div class="bg-gradient-to-br from-amber-50 to-yellow-50 border-2 border-amber-200 rounded-2xl p-5">
          <div class="flex justify-between items-center mb-2">
            <span class="text-gray-700 font-bold flex items-center">
              <.icon name="hero-clock" class="h-4 w-4 mr-1 text-amber-600" /> Pending
            </span>
            <span class="text-2xl font-extrabold text-amber-600">
              ${format_price(@earnings.pending_cents)}
            </span>
          </div>
          <p class="text-xs text-amber-700 font-medium">
            Will be paid out in next cycle
          </p>
        </div>
        <%!-- Completed Earnings --%>
        <div class="bg-gradient-to-br from-emerald-50 to-teal-50 border-2 border-emerald-200 rounded-2xl p-5">
          <div class="flex justify-between items-center mb-2">
            <span class="text-gray-700 font-bold flex items-center">
              <.icon name="hero-check-circle" class="h-4 w-4 mr-1 text-emerald-600" /> Paid Out
            </span>
            <span class="text-2xl font-extrabold text-emerald-600">
              ${format_price(@earnings.completed_cents)}
            </span>
          </div>
          <p class="text-xs text-emerald-700 font-medium">
            Successfully transferred
          </p>
        </div>
        <%!-- Jobs Completed --%>
        <div class="bg-gradient-to-br from-blue-50 to-cyan-50 border-2 border-blue-200 rounded-2xl p-5">
          <div class="flex justify-between items-center">
            <span class="text-gray-700 font-bold flex items-center">
              <.icon name="hero-briefcase" class="h-4 w-4 mr-1 text-blue-600" /> Jobs Completed
            </span>
            <span class="text-3xl font-extrabold text-blue-600">
              {@earnings.jobs_completed}
            </span>
          </div>
        </div>
        <%!-- Payout Method with modern card --%>
        <div class="border-t-2 border-gray-200 pt-6">
          <h3 class="text-base font-bold text-gray-900 mb-4 flex items-center">
            <.icon name="hero-credit-card" class="h-5 w-5 mr-2 text-gray-700" /> Payout Method
          </h3>
          <%= if @show_payout_form do %>
            <%!-- Payout Method Update Form --%>
            <div class="bg-gradient-to-br from-white to-gray-50 border-2 border-emerald-300 rounded-2xl p-5 space-y-4">
              <.form
                for={@payout_form}
                id="payout-method-form"
                phx-submit="update_payout_method"
                class="space-y-4"
              >
                <div>
                  <label class="block text-sm font-bold text-gray-900 mb-2">
                    Select Payout Method
                  </label>
                  <select
                    name="payout_method"
                    class="w-full px-4 py-3 border-2 border-gray-300 rounded-xl focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200 transition-colors"
                  >
                    <option value="stripe" selected={@provider.payout_method == :stripe}>
                      Stripe Connect (Bank Transfer)
                    </option>
                    <option value="mpesa" selected={@provider.payout_method == :mpesa}>
                      M-PESA (Mobile Money)
                    </option>
                  </select>
                </div>
                <div>
                  <label class="block text-sm font-bold text-gray-900 mb-2">
                    M-PESA Phone Number
                  </label>
                  <input
                    type="text"
                    name="mpesa_phone_number"
                    value={@provider.mpesa_phone_number || ""}
                    placeholder="+254712345678"
                    class="w-full px-4 py-3 border-2 border-gray-300 rounded-xl focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200 transition-colors"
                  />
                  <p class="text-xs text-gray-500 mt-1">
                    Required for M-PESA payouts
                  </p>
                </div>
                <div class="flex space-x-3">
                  <button
                    type="button"
                    phx-click="cancel_payout_update"
                    class="flex-1 px-4 py-3 bg-gray-100 text-gray-700 font-semibold rounded-xl hover:bg-gray-200 transition-all duration-200"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    class="flex-1 px-4 py-3 bg-gradient-to-r from-emerald-500 to-teal-500 text-white font-bold rounded-xl hover:from-emerald-600 hover:to-teal-600 shadow-md hover:shadow-lg transition-all duration-200"
                  >
                    Save Changes
                  </button>
                </div>
              </.form>
            </div>
          <% else %>
            <%!-- Current Payout Method Display --%>
            <div class="bg-gradient-to-br from-white to-gray-50 border-2 border-gray-200 rounded-2xl p-5 hover:border-emerald-300 transition-colors">
              <div class="flex items-center justify-between mb-4">
                <%= if @provider.payout_method == :stripe do %>
                  <div class="flex items-center">
                    <div class="flex items-center justify-center w-12 h-12 bg-gradient-to-br from-purple-100 to-blue-100 rounded-xl mr-4">
                      <span class="text-2xl">💳</span>
                    </div>
                    <div>
                      <p class="font-bold text-gray-900">Stripe Connect</p>
                      <p class="text-xs text-gray-600 font-medium">Bank transfer</p>
                      <%= if @provider.stripe_account_id do %>
                        <p class="text-xs text-emerald-600 font-semibold mt-1">✓ Connected</p>
                      <% else %>
                        <p class="text-xs text-amber-600 font-semibold mt-1">⚠ Not connected</p>
                      <% end %>
                    </div>
                  </div>
                <% else %>
                  <div class="flex items-center">
                    <div class="flex items-center justify-center w-12 h-12 bg-gradient-to-br from-green-100 to-emerald-100 rounded-xl mr-4">
                      <span class="text-2xl">📱</span>
                    </div>
                    <div>
                      <p class="font-bold text-gray-900">M-PESA</p>
                      <%= if @provider.mpesa_phone_number do %>
                        <p class="text-xs text-gray-600 font-medium">
                          {@provider.mpesa_phone_number}
                        </p>
                      <% else %>
                        <p class="text-xs text-amber-600 font-semibold">⚠ Phone number not set</p>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
              <button
                phx-click="show_payout_form"
                class="w-full px-4 py-2.5 bg-gradient-to-r from-gray-100 to-gray-200 text-gray-700 font-semibold rounded-xl hover:from-gray-200 hover:to-gray-300 transition-all duration-200 flex items-center justify-center"
              >
                <.icon name="hero-pencil-square" class="h-4 w-4 mr-2" /> Update Payout Method
              </button>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Event handlers

  @impl true
  def handle_event("accept_job", %{"job-id" => job_id}, socket) do
    provider_id = socket.assigns.provider_id

    with {:ok, job} <- Jobs.get_job(job_id),
         {:ok, accepted_job} <- Jobs.accept_job(job, provider_id) do
      handle_job_accepted(socket, accepted_job, job_id, provider_id)
    else
      {:error, :not_found} ->
        handle_job_not_found(socket)

      {:error, reason} ->
        handle_job_accept_error(socket, job_id, provider_id, reason)
    end
  end

  @impl true
  def handle_event("decline_job", %{"job-id" => job_id}, socket) do
    Logger.info("Provider declined job", %{
      provider_id: socket.assigns.provider_id,
      job_id: job_id
    })

    # Remove job from available jobs list
    available_jobs =
      Enum.reject(socket.assigns.available_jobs, fn job -> job.id == job_id end)

    socket =
      socket
      |> assign(available_jobs: available_jobs, error_message: nil)
      |> put_flash(:info, "Job declined")

    {:noreply, socket}
  end

  @impl true
  def handle_event("start_travel", _params, socket) do
    case socket.assigns.active_job do
      nil ->
        socket =
          socket
          |> assign(error_message: "No active job found")
          |> put_flash(:error, "No active job found")

        {:noreply, socket}

      job ->
        case Jobs.start_travel(job) do
          {:ok, updated_job} ->
            Logger.info("Provider started travel to job site", %{
              provider_id: socket.assigns.provider_id,
              job_id: job.id
            })

            socket =
              socket
              |> assign(active_job: updated_job, error_message: nil)
              |> put_flash(:info, "Started travel to job site")

            {:noreply, socket}

          {:error, reason} ->
            Logger.warning("Failed to start travel", %{
              provider_id: socket.assigns.provider_id,
              job_id: job.id,
              reason: reason
            })

            socket =
              socket
              |> assign(error_message: "Failed to start travel: #{reason}")
              |> put_flash(:error, "Failed to start travel: #{reason}")

            {:noreply, socket}
        end
    end
  end

  @impl true
  def handle_event("mark_on_site", _params, socket) do
    case socket.assigns.active_job do
      nil ->
        socket =
          socket
          |> assign(error_message: "No active job found")
          |> put_flash(:error, "No active job found")

        {:noreply, socket}

      job ->
        case Jobs.mark_on_site(job) do
          {:ok, updated_job} ->
            Logger.info("Provider marked as on site", %{
              provider_id: socket.assigns.provider_id,
              job_id: job.id
            })

            socket =
              socket
              |> assign(active_job: updated_job, error_message: nil)
              |> put_flash(:info, "Marked as on site")

            {:noreply, socket}

          {:error, reason} ->
            Logger.warning("Failed to mark on site", %{
              provider_id: socket.assigns.provider_id,
              job_id: job.id,
              reason: reason
            })

            socket =
              socket
              |> assign(error_message: "Failed to mark on site: #{reason}")
              |> put_flash(:error, "Failed to mark on site: #{reason}")

            {:noreply, socket}
        end
    end
  end

  @impl true
  def handle_event("validate_before_photo", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_after_photo", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("upload_before_photo", _params, socket) do
    case socket.assigns.active_job do
      nil ->
        handle_no_active_job(socket)

      job ->
        socket = handle_photo_upload(socket, job, :before_photo, :before)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("upload_after_photo", _params, socket) do
    case socket.assigns.active_job do
      nil ->
        handle_no_active_job(socket)

      job ->
        socket = handle_photo_upload(socket, job, :after_photo, :after)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("show_payout_form", _params, socket) do
    {:noreply, assign(socket, show_payout_form: true)}
  end

  @impl true
  def handle_event("cancel_payout_update", _params, socket) do
    {:noreply, assign(socket, show_payout_form: false)}
  end

  @impl true
  def handle_event("update_payout_method", params, socket) do
    provider = socket.assigns.provider
    payout_method = String.to_existing_atom(params["payout_method"])
    mpesa_phone_number = params["mpesa_phone_number"]

    # Validate M-PESA phone number if M-PESA is selected
    if payout_method == :mpesa and (is_nil(mpesa_phone_number) or mpesa_phone_number == "") do
      socket =
        socket
        |> assign(error_message: "M-PESA phone number is required")
        |> put_flash(:error, "M-PESA phone number is required")

      {:noreply, socket}
    else
      attrs =
        if payout_method == :mpesa do
          %{
            payout_method: payout_method,
            mpesa_phone_number: mpesa_phone_number
          }
        else
          %{payout_method: payout_method}
        end

      case Providers.update_provider(provider, attrs) do
        {:ok, updated_provider} ->
          Logger.info("Provider payout method updated", %{
            provider_id: provider.id,
            payout_method: payout_method
          })

          socket =
            socket
            |> assign(
              provider: updated_provider,
              show_payout_form: false,
              error_message: nil
            )
            |> put_flash(:info, "Payout method updated successfully!")

          {:noreply, socket}

        {:error, changeset} ->
          Logger.error("Failed to update payout method", %{
            provider_id: provider.id,
            errors: inspect(changeset.errors)
          })

          socket =
            socket
            |> assign(error_message: "Failed to update payout method")
            |> put_flash(:error, "Failed to update payout method")

          {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref, "type" => type}, socket) do
    upload_name = String.to_existing_atom(type)
    {:noreply, cancel_upload(socket, upload_name, ref)}
  end

  @impl true
  def handle_event("complete_job_with_photos", _params, socket) do
    case socket.assigns.active_job do
      nil ->
        handle_no_active_job(socket)

      job ->
        before_url = socket.assigns.before_photo_url
        after_url = socket.assigns.after_photo_url

        if before_url && after_url do
          socket = handle_job_completion(socket, job, before_url, after_url)
          {:noreply, socket}
        else
          handle_missing_photos(socket)
        end
    end
  end

  # PubSub message handlers

  @impl true
  def handle_info(%{event: "new_job_available", payload: %{job: job}}, socket) do
    Logger.info("New job available notification received", %{
      provider_id: socket.assigns.provider_id,
      job_id: job.id
    })

    # Add new job to available jobs list if not already present
    available_jobs =
      if Enum.any?(socket.assigns.available_jobs, fn j -> j.id == job.id end) do
        socket.assigns.available_jobs
      else
        [job | socket.assigns.available_jobs]
      end

    socket =
      socket
      |> assign(available_jobs: available_jobs)
      |> put_flash(:info, "New job available in your area!")

    {:noreply, socket}
  end

  @impl true
  def handle_info(%{event: "job_accepted", payload: %{job: job}}, socket) do
    # If this provider accepted the job, update active_job
    if job.provider_id == socket.assigns.provider_id do
      {:noreply, assign(socket, active_job: job)}
    else
      # Another provider accepted the job, remove from available jobs
      available_jobs =
        Enum.reject(socket.assigns.available_jobs, fn j -> j.id == job.id end)

      {:noreply, assign(socket, available_jobs: available_jobs)}
    end
  end

  @impl true
  def handle_info(%{event: "job_updated", payload: %{job: job}}, socket) do
    # Update active job if it matches
    if socket.assigns.active_job && socket.assigns.active_job.id == job.id do
      {:noreply, assign(socket, active_job: job)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(%{event: "job_completed", payload: %{job: job}}, socket) do
    # Clear active job and recalculate earnings
    if socket.assigns.active_job && socket.assigns.active_job.id == job.id do
      earnings = calculate_earnings(socket.assigns.provider_id)

      socket =
        socket
        |> assign(active_job: nil, earnings: earnings)
        |> put_flash(:success, "Job completed successfully!")

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(%{event: "job_cancelled", payload: %{job: job}}, socket) do
    # Remove from available jobs or clear active job
    available_jobs =
      Enum.reject(socket.assigns.available_jobs, fn j -> j.id == job.id end)

    active_job =
      if socket.assigns.active_job && socket.assigns.active_job.id == job.id do
        nil
      else
        socket.assigns.active_job
      end

    socket =
      socket
      |> assign(available_jobs: available_jobs, active_job: active_job)
      |> put_flash(:info, "Job was cancelled")

    {:noreply, socket}
  end

  # Catch-all for other PubSub messages
  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # Helper functions

  defp get_active_job(provider_id) do
    # Get the most recent job that's not completed or cancelled
    Jobs.list_jobs_for_provider(provider_id, [])
    |> Enum.find(fn job ->
      job.status in [:accepted, :en_route, :on_site]
    end)
  end

  defp calculate_earnings(provider_id) do
    # Get all completed jobs for this provider
    completed_jobs = Jobs.list_jobs_for_provider(provider_id, status: :completed)
    jobs_completed = length(completed_jobs)

    # Query payout transactions for this provider
    payout_transactions =
      from(t in TireDispatch.Payments.Transaction,
        where: t.provider_id == ^provider_id and t.type == :payout,
        select: %{
          status: t.status,
          amount_cents: t.amount_cents
        }
      )
      |> Repo.all()

    # Calculate pending earnings (payouts with status :pending)
    pending_cents =
      payout_transactions
      |> Enum.filter(fn t -> t.status == :pending end)
      |> Enum.map(fn t -> t.amount_cents end)
      |> Enum.sum()

    # Calculate completed earnings (payouts with status :completed)
    completed_cents =
      payout_transactions
      |> Enum.filter(fn t -> t.status == :completed end)
      |> Enum.map(fn t -> t.amount_cents end)
      |> Enum.sum()

    # Total earnings is the sum of pending and completed
    total_cents = pending_cents + completed_cents

    %{
      total_cents: total_cents,
      pending_cents: pending_cents,
      completed_cents: completed_cents,
      jobs_completed: jobs_completed
    }
  end

  # Helper functions for handle_event refactoring

  defp handle_no_active_job(socket) do
    socket =
      socket
      |> assign(error_message: "No active job found")
      |> put_flash(:error, "No active job found")

    {:noreply, socket}
  end

  defp handle_missing_photos(socket) do
    socket =
      socket
      |> assign(error_message: "Both before and after photos are required")
      |> put_flash(:error, "Both before and after photos are required")

    {:noreply, socket}
  end

  defp handle_job_accepted(socket, accepted_job, job_id, provider_id) do
    Logger.info("Provider accepted job", %{
      provider_id: provider_id,
      job_id: job_id
    })

    available_jobs = Enum.reject(socket.assigns.available_jobs, &(&1.id == job_id))

    socket =
      socket
      |> assign(
        active_job: accepted_job,
        available_jobs: available_jobs,
        error_message: nil
      )
      |> put_flash(:info, "Job accepted successfully!")

    {:noreply, socket}
  end

  defp handle_job_not_found(socket) do
    socket =
      socket
      |> assign(error_message: "Job not found")
      |> put_flash(:error, "Job not found")

    {:noreply, socket}
  end

  defp handle_job_accept_error(socket, job_id, provider_id, reason) do
    Logger.warning("Failed to accept job", %{
      provider_id: provider_id,
      job_id: job_id,
      reason: reason
    })

    socket =
      socket
      |> assign(error_message: "Failed to accept job: #{reason}")
      |> put_flash(:error, "Failed to accept job: #{reason}")

    {:noreply, socket}
  end

  defp handle_photo_upload(socket, job, upload_atom, photo_type) do
    socket = assign(socket, uploading: true)

    uploaded_files =
      consume_uploaded_entries(socket, upload_atom, fn %{path: path}, _entry ->
        upload_photo_to_s3_and_log(path, job.id, photo_type, socket.assigns.provider_id)
      end)

    handle_upload_result(socket, uploaded_files, photo_type)
  end

  defp upload_photo_to_s3_and_log(path, job_id, photo_type, provider_id) do
    case Photos.upload_photo_to_s3(path, job_id, photo_type) do
      {:ok, %{original: original_url, thumbnail: _thumbnail_url}} ->
        Logger.info("#{photo_type} photo uploaded successfully", %{
          job_id: job_id,
          provider_id: provider_id,
          url: original_url
        })

        {:ok, original_url}

      {:error, reason} ->
        Logger.error("Failed to upload #{photo_type} photo", %{
          job_id: job_id,
          provider_id: provider_id,
          reason: inspect(reason)
        })

        {:postpone, :error}
    end
  end

  defp handle_upload_result(socket, [url | _], :before) do
    socket
    |> assign(before_photo_url: url, uploading: false, error_message: nil)
    |> put_flash(:info, "Before photo uploaded successfully")
  end

  defp handle_upload_result(socket, [url | _], :after) do
    socket
    |> assign(after_photo_url: url, uploading: false, error_message: nil)
    |> put_flash(:info, "After photo uploaded successfully")
  end

  defp handle_upload_result(socket, [], photo_type) do
    socket
    |> assign(uploading: false, error_message: "Failed to upload #{photo_type} photo")
    |> put_flash(:error, "Failed to upload #{photo_type} photo")
  end

  defp handle_job_completion(socket, job, before_url, after_url) do
    case Jobs.complete_job(job, before_url, after_url) do
      {:ok, completed_job} ->
        handle_job_completion_success(socket, job, completed_job)

      {:error, reason} ->
        handle_job_completion_error(socket, job, reason)
    end
  end

  defp handle_job_completion_success(socket, job, completed_job) do
    Logger.info("Job completed successfully", %{
      job_id: job.id,
      provider_id: socket.assigns.provider_id,
      completed_at: completed_job.completed_at
    })

    earnings = calculate_earnings(socket.assigns.provider_id)

    socket
    |> assign(
      active_job: nil,
      before_photo_url: nil,
      after_photo_url: nil,
      earnings: earnings,
      error_message: nil
    )
    |> put_flash(:info, "Job completed successfully! Payment will be processed soon.")
  end

  defp handle_job_completion_error(socket, job, reason) do
    Logger.error("Failed to complete job", %{
      job_id: job.id,
      provider_id: socket.assigns.provider_id,
      reason: inspect(reason)
    })

    error_message = format_completion_error(reason)

    socket
    |> assign(error_message: error_message)
    |> put_flash(:error, error_message)
  end

  defp format_completion_error(changeset) when is_struct(changeset, Ecto.Changeset) do
    "Failed to complete job: validation error"
  end

  defp format_completion_error(message) when is_binary(message) do
    "Failed to complete job: #{message}"
  end

  defp format_completion_error(_), do: "Failed to complete job"

  # Formatting helper functions

  defp format_service_type(:flat_repair), do: "Flat Tire Repair"
  defp format_service_type(:nail_removal), do: "Nail Removal"
  defp format_service_type(:air_fill), do: "Air Fill"
  defp format_service_type(:new_tire), do: "New Tire Installation"
  defp format_service_type(:replacement), do: "Tire Replacement"
  defp format_service_type(_), do: "Unknown Service"

  defp format_urgency(:standard), do: "Standard"
  defp format_urgency(:rush), do: "Rush"
  defp format_urgency(:emergency), do: "Emergency"
  defp format_urgency(_), do: "Unknown"

  defp urgency_badge_class(:standard), do: "bg-blue-100 text-blue-700"
  defp urgency_badge_class(:rush), do: "bg-amber-100 text-amber-700"
  defp urgency_badge_class(:emergency), do: "bg-red-100 text-red-700"
  defp urgency_badge_class(_), do: "bg-gray-100 text-gray-700"

  defp format_vehicle(:compact), do: "Compact Car"
  defp format_vehicle(:suv), do: "SUV"
  defp format_vehicle(:truck), do: "Truck"
  defp format_vehicle(_), do: "Unknown"

  defp format_price(cents) when is_integer(cents) do
    dollars = cents / 100
    :erlang.float_to_binary(dollars, decimals: 2)
  end

  defp format_price(_), do: "0.00"

  defp format_job_status(:accepted), do: "Accepted"
  defp format_job_status(:en_route), do: "En Route"
  defp format_job_status(:on_site), do: "On Site"
  defp format_job_status(:completed), do: "Completed"
  defp format_job_status(_), do: "Unknown"

  defp status_emoji(:accepted), do: "✅"
  defp status_emoji(:en_route), do: "🚗"
  defp status_emoji(:on_site), do: "🔧"
  defp status_emoji(:completed), do: "🎉"
  defp status_emoji(_), do: "📋"

  defp format_distance(job, provider) do
    # Calculate distance using PostGIS
    case job.driver_location do
      %Geo.Point{coordinates: {long, lat}} ->
        distance_meters = Providers.calculate_provider_distance(provider, lat, long)

        if distance_meters do
          distance_km = distance_meters / 1000
          "#{Float.round(distance_km, 1)} km away"
        else
          "Distance unknown"
        end

      _ ->
        "Distance unknown"
    end
  end
end
