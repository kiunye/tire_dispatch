defmodule TireDispatch.Notifications.Email do
  @moduledoc """
  Email templates for tire dispatch notifications.

  Provides pre-built email templates for various job events.
  """

  import Swoosh.Email

  @doc """
  Creates a job completion email with receipt and photos.

  ## Arguments

    * `to` - Recipient email address
    * `job` - Job struct with completion details
    * `receipt_data` - Map with receipt information

  ## Returns

  Swoosh.Email struct ready to be sent
  """
  def job_completion_email(to, job, receipt_data) do
    new()
    |> to(to)
    |> from({"Tire Dispatch", "noreply@tiredispatch.com"})
    |> subject("Service Complete - Job ##{job.id}")
    |> html_body(job_completion_html(job, receipt_data))
    |> text_body(job_completion_text(job, receipt_data))
  end

  @doc """
  Creates a payment confirmation email.

  ## Arguments

    * `to` - Recipient email address
    * `job` - Job struct
    * `amount` - Payment amount in cents

  ## Returns

  Swoosh.Email struct ready to be sent
  """
  def payment_confirmation_email(to, job, amount) do
    new()
    |> to(to)
    |> from({"Tire Dispatch", "noreply@tiredispatch.com"})
    |> subject("Payment Confirmed - Job ##{String.slice(job.id, 0..7)}")
    |> html_body(payment_confirmation_html(job, amount))
    |> text_body(payment_confirmation_text(job, amount))
  end

  @doc """
  Creates a refund confirmation email.

  ## Arguments

    * `to` - Recipient email address
    * `job` - Job struct
    * `amount` - Refund amount in cents
    * `reason` - Refund reason

  ## Returns

  Swoosh.Email struct ready to be sent
  """
  def refund_confirmation_email(to, job, amount, reason) do
    new()
    |> to(to)
    |> from({"Tire Dispatch", "noreply@tiredispatch.com"})
    |> subject("Refund Processed - Job ##{String.slice(job.id, 0..7)}")
    |> html_body(refund_confirmation_html(job, amount, reason))
    |> text_body(refund_confirmation_text(job, amount, reason))
  end

  @doc """
  Creates a provider subscription update email.

  ## Arguments

    * `to` - Recipient email address
    * `provider` - Provider struct
    * `tier` - Subscription tier (premium or standard)

  ## Returns

  Swoosh.Email struct ready to be sent
  """
  def subscription_update_email(to, provider, tier) do
    new()
    |> to(to)
    |> from({"Tire Dispatch", "noreply@tiredispatch.com"})
    |> subject("Subscription Updated - #{String.capitalize(to_string(tier))} Tier")
    |> html_body(subscription_update_html(provider, tier))
    |> text_body(subscription_update_text(provider, tier))
  end

  # Private HTML templates

  defp job_completion_html(job, receipt_data) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(to right, #3b82f6, #06b6d4); color: white; padding: 30px; text-align: center; border-radius: 8px 8px 0 0; }
        .content { background: #f8fafc; padding: 30px; border-radius: 0 0 8px 8px; }
        .receipt { background: white; padding: 20px; border-radius: 8px; margin: 20px 0; }
        .receipt-row { display: flex; justify-content: space-between; padding: 10px 0; border-bottom: 1px solid #e2e8f0; }
        .total { font-size: 1.2em; font-weight: bold; color: #3b82f6; }
        .photos { display: flex; gap: 10px; margin: 20px 0; }
        .photo { width: 48%; border-radius: 8px; }
        .button { display: inline-block; background: linear-gradient(to right, #3b82f6, #06b6d4); color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; margin: 20px 0; }
        .footer { text-align: center; color: #64748b; font-size: 0.9em; margin-top: 30px; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>Service Complete!</h1>
          <p>Your tire service has been successfully completed</p>
        </div>
        <div class="content">
          <h2>Job Details</h2>
          <div class="receipt">
            <div class="receipt-row">
              <span>Job ID:</span>
              <span>##{job.id}</span>
            </div>
            <div class="receipt-row">
              <span>Service Type:</span>
              <span>#{format_service_type(job.service_type)}</span>
            </div>
            <div class="receipt-row">
              <span>Vehicle Type:</span>
              <span>#{format_vehicle_type(job.vehicle_type)}</span>
            </div>
            <div class="receipt-row">
              <span>Completed At:</span>
              <span>#{format_datetime(job.completed_at)}</span>
            </div>
            <div class="receipt-row total">
              <span>Total Amount:</span>
              <span>#{format_currency(receipt_data.amount_cents)}</span>
            </div>
          </div>

          #{if job.before_photo_url && job.after_photo_url do
      """
      <h3>Before & After Photos</h3>
      <div class="photos">
        <img src="#{job.before_photo_url}" alt="Before" class="photo">
        <img src="#{job.after_photo_url}" alt="After" class="photo">
      </div>
      """
    else
      ""
    end}

          <p>Thank you for using Tire Dispatch! We hope you had a great experience.</p>

          <a href="#{receipt_data.receipt_url}" class="button">View Full Receipt</a>
        </div>
        <div class="footer">
          <p>Tire Dispatch - Roadside Tire Service On Demand</p>
          <p>Questions? Contact us at support@tiredispatch.com</p>
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp job_completion_text(job, receipt_data) do
    """
    SERVICE COMPLETE

    Your tire service has been successfully completed!

    Job Details:
    - Job ID: ##{job.id}
    - Service Type: #{format_service_type(job.service_type)}
    - Vehicle Type: #{format_vehicle_type(job.vehicle_type)}
    - Completed At: #{format_datetime(job.completed_at)}
    - Total Amount: #{format_currency(receipt_data.amount_cents)}

    View your full receipt: #{receipt_data.receipt_url}

    Thank you for using Tire Dispatch!

    ---
    Tire Dispatch - Roadside Tire Service On Demand
    Questions? Contact us at support@tiredispatch.com
    """
  end

  defp payment_confirmation_html(job, amount) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(to right, #10b981, #059669); color: white; padding: 30px; text-align: center; border-radius: 8px 8px 0 0; }
        .content { background: #f8fafc; padding: 30px; border-radius: 0 0 8px 8px; }
        .amount { font-size: 2em; font-weight: bold; color: #10b981; text-align: center; margin: 20px 0; }
        .footer { text-align: center; color: #64748b; font-size: 0.9em; margin-top: 30px; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>✓ Payment Confirmed</h1>
        </div>
        <div class="content">
          <div class="amount">#{format_currency(amount)}</div>
          <p>Your payment has been successfully processed for Job ##{String.slice(job.id, 0..7)}.</p>
          <p>A provider will be assigned to your job shortly. You'll receive an SMS notification when a provider accepts your request.</p>
          <p><strong>Service Type:</strong> #{format_service_type(job.service_type)}</p>
          <p><strong>Urgency:</strong> #{format_urgency(job.urgency_tier)}</p>
        </div>
        <div class="footer">
          <p>Tire Dispatch - Roadside Tire Service On Demand</p>
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp payment_confirmation_text(job, amount) do
    """
    PAYMENT CONFIRMED

    Your payment of #{format_currency(amount)} has been successfully processed.

    Job ID: ##{String.slice(job.id, 0..7)}
    Service Type: #{format_service_type(job.service_type)}
    Urgency: #{format_urgency(job.urgency_tier)}

    A provider will be assigned to your job shortly. You'll receive an SMS notification when a provider accepts your request.

    ---
    Tire Dispatch - Roadside Tire Service On Demand
    """
  end

  defp refund_confirmation_html(job, amount, reason) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(to right, #3b82f6, #06b6d4); color: white; padding: 30px; text-align: center; border-radius: 8px 8px 0 0; }
        .content { background: #f8fafc; padding: 30px; border-radius: 0 0 8px 8px; }
        .amount { font-size: 2em; font-weight: bold; color: #3b82f6; text-align: center; margin: 20px 0; }
        .info-box { background: white; padding: 20px; border-radius: 8px; margin: 20px 0; border-left: 4px solid #3b82f6; }
        .footer { text-align: center; color: #64748b; font-size: 0.9em; margin-top: 30px; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>Refund Processed</h1>
        </div>
        <div class="content">
          <div class="amount">#{format_currency(amount)}</div>
          <p>Your refund has been processed for Job ##{String.slice(job.id, 0..7)}.</p>

          <div class="info-box">
            <p><strong>Reason:</strong> #{reason}</p>
            <p><strong>Expected Timeline:</strong> 5-10 business days</p>
            <p>The refund will appear on your original payment method.</p>
          </div>

          <p>We apologize for any inconvenience. If you have any questions, please contact our support team.</p>
        </div>
        <div class="footer">
          <p>Tire Dispatch - Roadside Tire Service On Demand</p>
          <p>Questions? Contact us at support@tiredispatch.com</p>
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp refund_confirmation_text(job, amount, reason) do
    """
    REFUND PROCESSED

    Your refund of #{format_currency(amount)} has been processed.

    Job ID: ##{String.slice(job.id, 0..7)}
    Reason: #{reason}
    Expected Timeline: 5-10 business days

    The refund will appear on your original payment method.

    We apologize for any inconvenience. If you have any questions, please contact our support team at support@tiredispatch.com.

    ---
    Tire Dispatch - Roadside Tire Service On Demand
    """
  end

  defp subscription_update_html(provider, tier) do
    tier_name = String.capitalize(to_string(tier))
    benefits = if tier == :premium, do: premium_benefits(), else: standard_benefits()

    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(to right, #8b5cf6, #6366f1); color: white; padding: 30px; text-align: center; border-radius: 8px 8px 0 0; }
        .content { background: #f8fafc; padding: 30px; border-radius: 0 0 8px 8px; }
        .tier-badge { display: inline-block; background: linear-gradient(to right, #8b5cf6, #6366f1); color: white; padding: 8px 16px; border-radius: 20px; font-weight: bold; }
        .benefits { background: white; padding: 20px; border-radius: 8px; margin: 20px 0; }
        .benefit { padding: 10px 0; border-bottom: 1px solid #e2e8f0; }
        .benefit:last-child { border-bottom: none; }
        .footer { text-align: center; color: #64748b; font-size: 0.9em; margin-top: 30px; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>Subscription Updated</h1>
          <p>You're now on the <span class="tier-badge">#{tier_name}</span> tier</p>
        </div>
        <div class="content">
          <p>Hi #{provider.user.email},</p>
          <p>Your subscription has been updated successfully!</p>

          <div class="benefits">
            <h3>Your #{tier_name} Benefits:</h3>
            #{Enum.map_join(benefits, "", fn benefit -> "<div class='benefit'>✓ #{benefit}</div>" end)}
          </div>

          <p>Thank you for being part of the Tire Dispatch provider network!</p>
        </div>
        <div class="footer">
          <p>Tire Dispatch - Roadside Tire Service On Demand</p>
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp subscription_update_text(provider, tier) do
    tier_name = String.capitalize(to_string(tier))
    benefits = if tier == :premium, do: premium_benefits(), else: standard_benefits()

    """
    SUBSCRIPTION UPDATED

    Hi #{provider.user.email},

    You're now on the #{tier_name} tier!

    Your #{tier_name} Benefits:
    #{Enum.map_join(benefits, "\n", fn benefit -> "✓ #{benefit}" end)}

    Thank you for being part of the Tire Dispatch provider network!

    ---
    Tire Dispatch - Roadside Tire Service On Demand
    """
  end

  # Helper functions

  defp format_service_type(service_type) do
    service_type
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp format_vehicle_type(vehicle_type) do
    vehicle_type
    |> to_string()
    |> String.upcase()
  end

  defp format_urgency(urgency_tier) do
    urgency_tier
    |> to_string()
    |> String.capitalize()
  end

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%B %d, %Y at %I:%M %p")
  end

  defp format_currency(amount_cents) do
    dollars = amount_cents / 100
    "$#{:erlang.float_to_binary(dollars, decimals: 2)}"
  end

  defp premium_benefits do
    [
      "Priority job visibility (30 seconds early access)",
      "Higher placement in provider search results",
      "Dedicated support line",
      "Advanced analytics dashboard",
      "Custom branding options"
    ]
  end

  defp standard_benefits do
    [
      "Access to all job requests",
      "Standard support",
      "Basic analytics",
      "Secure payment processing"
    ]
  end
end
