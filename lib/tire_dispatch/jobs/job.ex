defmodule TireDispatch.Jobs.Job do
  @moduledoc """
  Job schema for tire repair and replacement requests.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "jobs" do
    field :service_type, Ecto.Enum,
      values: [:flat_repair, :nail_removal, :air_fill, :new_tire, :replacement]

    field :status, Ecto.Enum,
      values: [:open, :accepted, :en_route, :on_site, :completed, :cancelled],
      default: :open

    field :urgency_tier, Ecto.Enum, values: [:standard, :rush, :emergency]
    field :vehicle_type, Ecto.Enum, values: [:compact, :suv, :truck]

    field :driver_location, Geo.PostGIS.Geometry
    field :provider_location, Geo.PostGIS.Geometry

    field :estimated_price_cents, :integer
    field :final_price_cents, :integer

    field :issue_notes, :string
    field :photos, {:array, :string}, default: []
    field :before_photo_url, :string
    field :after_photo_url, :string
    field :cancellation_reason, :string
    field :completed_at, :utc_datetime_usec

    belongs_to :driver, TireDispatch.Users.User
    belongs_to :provider, TireDispatch.Users.User

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new job.
  """
  def changeset(job, attrs) do
    job
    |> cast(attrs, [
      :service_type,
      :status,
      :urgency_tier,
      :vehicle_type,
      :driver_location,
      :provider_location,
      :estimated_price_cents,
      :final_price_cents,
      :issue_notes,
      :photos,
      :before_photo_url,
      :after_photo_url,
      :cancellation_reason,
      :completed_at,
      :driver_id,
      :provider_id
    ])
    |> validate_required([
      :service_type,
      :urgency_tier,
      :vehicle_type,
      :driver_location,
      :estimated_price_cents,
      :driver_id
    ])
    |> validate_inclusion(:service_type, [
      :flat_repair,
      :nail_removal,
      :air_fill,
      :new_tire,
      :replacement
    ])
    |> validate_inclusion(:status, [:open, :accepted, :en_route, :on_site, :completed, :cancelled])
    |> validate_inclusion(:urgency_tier, [:standard, :rush, :emergency])
    |> validate_inclusion(:vehicle_type, [:compact, :suv, :truck])
    |> validate_number(:estimated_price_cents, greater_than: 0)
    |> validate_number(:final_price_cents, greater_than: 0)
    |> foreign_key_constraint(:driver_id)
    |> foreign_key_constraint(:provider_id)
  end

  @doc """
  Changeset for updating job status.
  """
  def status_changeset(job, attrs) do
    job
    |> cast(attrs, [:status, :provider_id, :provider_location, :completed_at])
    |> validate_required([:status])
    |> validate_inclusion(:status, [:open, :accepted, :en_route, :on_site, :completed, :cancelled])
  end

  @doc """
  Changeset for completing a job with photos.
  """
  def completion_changeset(job, attrs) do
    job
    |> cast(attrs, [
      :status,
      :before_photo_url,
      :after_photo_url,
      :final_price_cents,
      :completed_at
    ])
    |> validate_required([:status, :before_photo_url, :after_photo_url, :completed_at])
    |> validate_inclusion(:status, [:completed])
  end
end
