-- RevTrack production-target foundation, NOT connected to the Go demo yet.
-- Requires PostgreSQL 18+, PostGIS and btree_gist, run by a migration role.
BEGIN;
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE SCHEMA revtrack;
REVOKE ALL ON SCHEMA revtrack FROM PUBLIC;

CREATE TABLE revtrack.tenants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  slug text NOT NULL UNIQUE,
  timezone text NOT NULL DEFAULT 'Asia/Jakarta',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE revtrack.tenant_members (
  tenant_id uuid NOT NULL REFERENCES revtrack.tenants(id),
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  oidc_issuer text NOT NULL,
  oidc_subject text NOT NULL,
  role text NOT NULL CHECK (role IN ('owner','dispatcher','fleet_manager','finance','technician','driver','auditor')),
  active boolean NOT NULL DEFAULT true,
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, oidc_issuer, oidc_subject)
);

CREATE TABLE revtrack.vehicles (
  tenant_id uuid NOT NULL REFERENCES revtrack.tenants(id),
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  asset_code text NOT NULL,
  plate text,
  vin_ciphertext bytea,
  asset_type text NOT NULL CHECK (asset_type IN ('car','van','truck','heavy_equipment','other')),
  powertrain text NOT NULL CHECK (powertrain IN ('ev','ice','hybrid','diesel','other')),
  make text NOT NULL,
  model text NOT NULL,
  model_year integer CHECK (model_year BETWEEN 1900 AND 2200),
  lifecycle text NOT NULL DEFAULT 'onboarding' CHECK (lifecycle IN ('onboarding','available','rented','maintenance','recovery','retired')),
  capability_profile jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, asset_code)
);

CREATE TABLE revtrack.drivers (
  tenant_id uuid NOT NULL REFERENCES revtrack.tenants(id),
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  member_id uuid,
  display_name text NOT NULL,
  contact_ciphertext bytea,
  license_reference text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','active','suspended','archived')),
  PRIMARY KEY (tenant_id, id),
  FOREIGN KEY (tenant_id, member_id) REFERENCES revtrack.tenant_members(tenant_id, id)
);

CREATE TABLE revtrack.driver_assignments (
  tenant_id uuid NOT NULL REFERENCES revtrack.tenants(id),
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  vehicle_id uuid NOT NULL,
  driver_id uuid NOT NULL,
  assigned_by uuid NOT NULL,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz,
  PRIMARY KEY (tenant_id, id),
  CHECK (ends_at IS NULL OR ends_at > starts_at),
  FOREIGN KEY (tenant_id, vehicle_id) REFERENCES revtrack.vehicles(tenant_id, id),
  FOREIGN KEY (tenant_id, driver_id) REFERENCES revtrack.drivers(tenant_id, id),
  FOREIGN KEY (tenant_id, assigned_by) REFERENCES revtrack.tenant_members(tenant_id, id),
  EXCLUDE USING gist (tenant_id WITH =, vehicle_id WITH =, tstzrange(starts_at, ends_at, '[)') WITH &&),
  EXCLUDE USING gist (tenant_id WITH =, driver_id WITH =, tstzrange(starts_at, ends_at, '[)') WITH &&)
);

CREATE TABLE revtrack.devices (
  tenant_id uuid NOT NULL REFERENCES revtrack.tenants(id),
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  hardware_uid text NOT NULL UNIQUE,
  model text NOT NULL,
  protocol text NOT NULL,
  firmware_version text,
  credential_key_reference text NOT NULL,
  status text NOT NULL DEFAULT 'provisioning' CHECK (status IN ('provisioning','active','quarantined','revoked','retired')),
  PRIMARY KEY (tenant_id, id)
);

CREATE TABLE revtrack.device_installations (
  tenant_id uuid NOT NULL REFERENCES revtrack.tenants(id),
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  device_id uuid NOT NULL,
  vehicle_id uuid NOT NULL,
  installation_role text NOT NULL CHECK (installation_role IN ('primary','backup','sensor','intercom')),
  installed_at timestamptz NOT NULL,
  removed_at timestamptz,
  installer_member_id uuid,
  verification_evidence_reference text,
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, id, device_id, vehicle_id),
  CHECK (removed_at IS NULL OR removed_at > installed_at),
  FOREIGN KEY (tenant_id, device_id) REFERENCES revtrack.devices(tenant_id, id),
  FOREIGN KEY (tenant_id, vehicle_id) REFERENCES revtrack.vehicles(tenant_id, id),
  FOREIGN KEY (tenant_id, installer_member_id) REFERENCES revtrack.tenant_members(tenant_id, id),
  EXCLUDE USING gist (tenant_id WITH =, device_id WITH =, tstzrange(installed_at, removed_at, '[)') WITH &&)
);
CREATE UNIQUE INDEX one_current_primary_tracker ON revtrack.device_installations (tenant_id, vehicle_id)
  WHERE removed_at IS NULL AND installation_role = 'primary';

CREATE TABLE revtrack.device_sessions (
  tenant_id uuid NOT NULL REFERENCES revtrack.tenants(id),
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  device_id uuid NOT NULL,
  issued_at timestamptz NOT NULL,
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, id, device_id),
  CHECK (expires_at > issued_at),
  FOREIGN KEY (tenant_id, device_id) REFERENCES revtrack.devices(tenant_id, id)
);

CREATE TABLE revtrack.telemetry_events (
  tenant_id uuid NOT NULL REFERENCES revtrack.tenants(id),
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  device_id uuid NOT NULL,
  vehicle_id uuid NOT NULL,
  installation_id uuid NOT NULL,
  session_id uuid NOT NULL,
  event_id text NOT NULL,
  sequence bigint NOT NULL CHECK (sequence >= 0),
  recorded_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now(),
  position geography(Point,4326) NOT NULL,
  speed_kph numeric(6,2) CHECK (speed_kph BETWEEN 0 AND 400),
  accuracy_m numeric(9,2) CHECK (accuracy_m BETWEEN 0 AND 100000),
  ignition boolean,
  battery_percent numeric(5,2) CHECK (battery_percent BETWEEN 0 AND 100),
  fuel_percent numeric(5,2) CHECK (fuel_percent BETWEEN 0 AND 100),
  odometer_km numeric(14,3) CHECK (odometer_km >= 0),
  quality_flags text[] NOT NULL DEFAULT '{}',
  raw_payload_sha256 bytea NOT NULL CHECK (octet_length(raw_payload_sha256) = 32),
  raw_object_reference text,
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, id, vehicle_id),
  UNIQUE (tenant_id, device_id, event_id),
  UNIQUE (tenant_id, device_id, session_id, sequence),
  FOREIGN KEY (tenant_id, installation_id, device_id, vehicle_id)
    REFERENCES revtrack.device_installations(tenant_id, id, device_id, vehicle_id),
  FOREIGN KEY (tenant_id, session_id, device_id)
    REFERENCES revtrack.device_sessions(tenant_id, id, device_id)
);
CREATE INDEX telemetry_vehicle_time ON revtrack.telemetry_events (tenant_id, vehicle_id, recorded_at DESC);
CREATE INDEX telemetry_received_brin ON revtrack.telemetry_events USING brin (received_at);
CREATE INDEX telemetry_position_gist ON revtrack.telemetry_events USING gist (position);

CREATE TABLE revtrack.vehicle_latest (
  tenant_id uuid NOT NULL REFERENCES revtrack.tenants(id),
  vehicle_id uuid NOT NULL,
  telemetry_id uuid NOT NULL,
  recorded_at timestamptz NOT NULL,
  last_received_at timestamptz NOT NULL,
  PRIMARY KEY (tenant_id, vehicle_id),
  FOREIGN KEY (tenant_id, telemetry_id, vehicle_id) REFERENCES revtrack.telemetry_events(tenant_id, id, vehicle_id)
);

CREATE TABLE revtrack.geofences (
  tenant_id uuid NOT NULL REFERENCES revtrack.tenants(id),
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  boundary geography(MultiPolygon,4326) NOT NULL,
  dwell_seconds integer NOT NULL DEFAULT 30 CHECK (dwell_seconds BETWEEN 0 AND 3600),
  uncertainty_buffer_m integer NOT NULL DEFAULT 50 CHECK (uncertainty_buffer_m BETWEEN 0 AND 10000),
  active boolean NOT NULL DEFAULT true,
  PRIMARY KEY (tenant_id, id),
  CHECK (ST_IsValid(boundary::geometry))
);
CREATE INDEX geofence_boundary_gist ON revtrack.geofences USING gist (boundary);
CREATE TABLE revtrack.vehicle_geofences (
  tenant_id uuid NOT NULL REFERENCES revtrack.tenants(id),
  vehicle_id uuid NOT NULL,
  geofence_id uuid NOT NULL,
  policy text NOT NULL CHECK (policy IN ('must_remain_inside','must_remain_outside','entry_exit_notice')),
  PRIMARY KEY (tenant_id, vehicle_id, geofence_id),
  FOREIGN KEY (tenant_id, vehicle_id) REFERENCES revtrack.vehicles(tenant_id, id),
  FOREIGN KEY (tenant_id, geofence_id) REFERENCES revtrack.geofences(tenant_id, id)
);

CREATE TABLE revtrack.alerts (
  tenant_id uuid NOT NULL REFERENCES revtrack.tenants(id),
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  vehicle_id uuid NOT NULL,
  evidence_telemetry_id uuid,
  alert_type text NOT NULL,
  severity text NOT NULL CHECK (severity IN ('info','low','medium','high','critical')),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','acknowledged','investigating','resolved','dismissed')),
  confidence numeric(4,3) CHECK (confidence BETWEEN 0 AND 1),
  rule_version text NOT NULL,
  opened_at timestamptz NOT NULL DEFAULT now(),
  acknowledged_by uuid,
  acknowledged_at timestamptz,
  PRIMARY KEY (tenant_id, id),
  FOREIGN KEY (tenant_id, vehicle_id) REFERENCES revtrack.vehicles(tenant_id, id),
  FOREIGN KEY (tenant_id, evidence_telemetry_id, vehicle_id) REFERENCES revtrack.telemetry_events(tenant_id, id, vehicle_id),
  FOREIGN KEY (tenant_id, acknowledged_by) REFERENCES revtrack.tenant_members(tenant_id, id)
);
CREATE INDEX alert_queue ON revtrack.alerts (tenant_id, status, opened_at DESC);

CREATE TABLE revtrack.audit_events (
  tenant_id uuid NOT NULL REFERENCES revtrack.tenants(id),
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  actor_member_id uuid,
  actor_service text,
  action text NOT NULL,
  resource_type text NOT NULL,
  resource_id text NOT NULL,
  request_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  redacted_change jsonb NOT NULL DEFAULT '{}',
  PRIMARY KEY (tenant_id, id),
  CHECK (actor_member_id IS NOT NULL OR actor_service IS NOT NULL),
  FOREIGN KEY (tenant_id, actor_member_id) REFERENCES revtrack.tenant_members(tenant_id, id)
);

CREATE TABLE revtrack.ai_proposals (
  tenant_id uuid NOT NULL REFERENCES revtrack.tenants(id),
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  agent_name text NOT NULL,
  model_version text NOT NULL,
  policy_version text NOT NULL,
  proposal_type text NOT NULL,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','awaiting_approval','approved','rejected','expired','executed','failed')),
  explanation text NOT NULL,
  evidence_references jsonb NOT NULL DEFAULT '[]',
  requested_action jsonb NOT NULL,
  approved_by uuid,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  FOREIGN KEY (tenant_id, approved_by) REFERENCES revtrack.tenant_members(tenant_id, id)
);

CREATE TABLE revtrack.outbox_events (
  tenant_id uuid NOT NULL REFERENCES revtrack.tenants(id),
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  topic text NOT NULL,
  aggregate_id uuid NOT NULL,
  idempotency_key text NOT NULL,
  payload jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz,
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, idempotency_key)
);
CREATE INDEX outbox_pending ON revtrack.outbox_events (created_at) WHERE published_at IS NULL;

-- The Go service must select tenant from a verified OIDC membership, then use
-- SELECT set_config('app.tenant_id', $1, true) INSIDE every DB transaction.
-- Never expose SQL or allow the caller to choose this setting directly.
ALTER TABLE revtrack.tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE revtrack.tenants FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_boundary ON revtrack.tenants
  USING (id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)
  WITH CHECK (id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);

DO $$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'tenant_members','vehicles','drivers','driver_assignments','devices',
    'device_installations','device_sessions','telemetry_events','vehicle_latest',
    'geofences','vehicle_geofences','alerts','audit_events','ai_proposals','outbox_events'
  ] LOOP
    EXECUTE format('ALTER TABLE revtrack.%I ENABLE ROW LEVEL SECURITY', table_name);
    EXECUTE format('ALTER TABLE revtrack.%I FORCE ROW LEVEL SECURITY', table_name);
    EXECUTE format('CREATE POLICY tenant_boundary ON revtrack.%I USING (tenant_id = NULLIF(current_setting(''app.tenant_id'', true), '''')::uuid) WITH CHECK (tenant_id = NULLIF(current_setting(''app.tenant_id'', true), '''')::uuid)', table_name);
  END LOOP;
END $$;

-- No runtime grants here: provision roles separately with NOBYPASSRLS/NOSUPERUSER.
-- Telemetry/audit writers should receive INSERT/SELECT only; tenant RLS does not
-- itself implement RBAC, immutable audit, OIDC validation, or device authentication.
COMMIT;
