package demo

import (
	"math"
	"regexp"
	"sort"
	"strconv"
	"sync"
	"time"
)

const MaxPoints = 500
const MaxAlerts = 200

var eventPattern = regexp.MustCompile(`^[A-Za-z0-9_-]{8,80}$`)

type deviceBinding struct {
	tenantID, vehicleID string
	speedLimitKph       float64
}
type cursor struct {
	sequence           int64
	eventIDs           map[string]struct{}
	eventOrder         *Ring[string]
	outsideCount       int
	inBreach, speeding bool
}
type tenantData struct {
	vehicles    map[string]Vehicle
	points      map[string]*Ring[Point]
	alerts      *Ring[Alert]
	drivers     map[string]Driver
	audit       *Ring[AuditEvent]
	assignments *Ring[Assignment]
	bookings    map[string]Booking
	workOrders  map[string]WorkOrder
}
type Store struct {
	mu       sync.RWMutex
	clock    func() time.Time
	tenants  map[string]*tenantData
	devices  map[string]deviceBinding
	cursors  map[string]*cursor
	dataFile string
}

func NewStore(clock func() time.Time) *Store {
	if clock == nil {
		clock = time.Now
	}
	s := &Store{clock: clock, tenants: make(map[string]*tenantData), devices: map[string]deviceBinding{"dev-001": {"tenant-demo", "veh-001", 80}, "dev-other": {"tenant-other", "veh-other", 80}}, cursors: make(map[string]*cursor)}
	s.seed()
	return s
}
func (s *Store) current(vehicle Vehicle) Vehicle {
	seen, _ := time.Parse(isoLayout, vehicle.LastSeenAt)
	if s.clock().Sub(seen) > 5*time.Minute {
		vehicle.Status = "offline"
		vehicle.Signal = "offline"
	}
	return vehicle
}
func (s *Store) Fleet(tenantID string) Fleet {
	s.mu.RLock()
	defer s.mu.RUnlock()
	result := Fleet{Mode: "demo", GeneratedAt: iso(s.clock()), Vehicles: []Vehicle{}}
	if tenant := s.tenants[tenantID]; tenant != nil {
		for _, v := range tenant.vehicles {
			result.Vehicles = append(result.Vehicles, s.current(v))
		}
		for _, a := range tenant.alerts.Values() {
			if a.Status == "open" {
				result.Summary.Alerts++
			}
		}
	}
	sort.Slice(result.Vehicles, func(i, j int) bool { return result.Vehicles[i].ID < result.Vehicles[j].ID })
	result.Summary.Total = len(result.Vehicles)
	for _, v := range result.Vehicles {
		switch v.Status {
		case "moving":
			result.Summary.Moving++
		case "idle":
			result.Summary.Idle++
		case "offline":
			result.Summary.Offline++
		}
	}
	return result
}
func (s *Store) Vehicle(tenantID, vehicleID string) (Vehicle, *APIError) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if tenant := s.tenants[tenantID]; tenant != nil {
		if v, ok := tenant.vehicles[vehicleID]; ok {
			return s.current(v), nil
		}
	}
	return Vehicle{}, fail(404, "not_found", "Unit tidak ditemukan.")
}
func (s *Store) Telemetry(tenantID, vehicleID string) ([]Point, *APIError) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if tenant := s.tenants[tenantID]; tenant != nil {
		if points := tenant.points[vehicleID]; points != nil {
			return points.Values(), nil
		}
	}
	return nil, fail(404, "not_found", "Unit tidak ditemukan.")
}
func (s *Store) Alerts(tenantID string) []Alert {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if tenant := s.tenants[tenantID]; tenant != nil {
		result := tenant.alerts.Values()
		sort.SliceStable(result, func(i, j int) bool { return result[i].CreatedAt > result[j].CreatedAt })
		return result
	}
	return []Alert{}
}

func validate(input TelemetryInput, now time.Time) (time.Time, *APIError) {
	if !eventPattern.MatchString(input.EventID) {
		return time.Time{}, fail(422, "invalid_telemetry", "eventId harus 8–80 huruf, angka, dash atau underscore.")
	}
	if input.Sequence < 1 || input.Sequence > 9007199254740991 {
		return time.Time{}, fail(422, "invalid_telemetry", "sequence harus integer positif yang aman untuk JSON.")
	}
	timestamp, err := time.Parse(isoLayout, input.RecordedAt)
	if err != nil || iso(timestamp) != input.RecordedAt || timestamp.After(now.Add(30*time.Second)) || timestamp.Before(now.Add(-24*time.Hour)) {
		return time.Time{}, fail(422, "invalid_timestamp", "Waktu harus ISO UTC milliseconds, maksimal 24 jam lama dan 30 detik ke depan.")
	}
	for _, field := range []struct {
		name     string
		value    *float64
		min, max float64
		required bool
	}{
		{"latitude", input.Latitude, -90, 90, true}, {"longitude", input.Longitude, -180, 180, true}, {"speedKph", input.SpeedKph, 0, 250, true}, {"accuracyM", input.AccuracyM, 0, 10000, true},
		{"batteryPercent", input.BatteryPercent, 0, 100, false}, {"fuelPercent", input.FuelPercent, 0, 100, false}, {"odometerKm", input.OdometerKm, 0, 10000000, false},
	} {
		if field.value == nil {
			if field.required {
				return time.Time{}, fail(422, "invalid_telemetry", field.name+" wajib diisi.")
			}
			continue
		}
		if math.IsNaN(*field.value) || math.IsInf(*field.value, 0) || *field.value < field.min || *field.value > field.max {
			return time.Time{}, fail(422, "invalid_telemetry", field.name+" di luar rentang.")
		}
	}
	if input.Ignition == nil {
		return time.Time{}, fail(422, "invalid_telemetry", "ignition wajib berupa boolean.")
	}
	return timestamp, nil
}

// Ingest is atomic across history, latest position, replay cursors and alerts.
// Demo rejects late fixes; production stores valid late history separately.
func (s *Store) Ingest(principal Credential, input TelemetryInput) (Accepted, *APIError) {
	s.mu.Lock()
	defer s.mu.Unlock()
	device, ok := s.devices[principal.DeviceID]
	if !ok || device.tenantID != principal.TenantID {
		return Accepted{}, fail(403, "device_unassigned", "Perangkat tidak memiliki pemasangan aktif.")
	}
	timestamp, problem := validate(input, s.clock())
	if problem != nil {
		return Accepted{}, problem
	}
	tenant := s.tenants[device.tenantID]
	vehicle := tenant.vehicles[device.vehicleID]
	if (vehicle.Powertrain == "ev" && input.FuelPercent != nil) || (vehicle.Powertrain != "ev" && input.BatteryPercent != nil) {
		return Accepted{}, fail(422, "unsupported_measurement", "Jenis energi tidak sesuai kapabilitas unit simulasi.")
	}
	previous := s.cursors[principal.DeviceID]
	if previous != nil {
		_, duplicate := previous.eventIDs[input.EventID]
		if duplicate || input.Sequence <= previous.sequence {
			return Accepted{}, fail(409, "replayed_event", "eventId atau sequence sudah diterima.")
		}
	}
	lastPosition, _ := time.Parse(isoLayout, vehicle.LastPositionAt)
	if !timestamp.After(lastPosition) {
		return Accepted{}, fail(409, "out_of_order", "Posisi lama tidak boleh mengganti posisi terkini.")
	}
	if input.OdometerKm != nil && *input.OdometerKm < vehicle.OdometerKm {
		return Accepted{}, fail(422, "odometer_rollback", "Odometer menurun; perlu investigasi atau reset terotorisasi.")
	}
	before := s.backupLocked()
	if previous == nil {
		previous = &cursor{eventIDs: make(map[string]struct{}), eventOrder: NewRing[string](MaxPoints)}
		s.cursors[principal.DeviceID] = previous
	}
	point := Point{EventID: input.EventID, Sequence: input.Sequence, RecordedAt: input.RecordedAt, ReceivedAt: iso(s.clock()), Latitude: *input.Latitude, Longitude: *input.Longitude, SpeedKph: *input.SpeedKph, AccuracyM: *input.AccuracyM, BatteryPercent: input.BatteryPercent, FuelPercent: input.FuelPercent, OdometerKm: input.OdometerKm, Source: "simulator"}
	tenant.points[device.vehicleID].Append(point)
	if evicted, yes := previous.eventOrder.Append(input.EventID); yes {
		delete(previous.eventIDs, evicted)
	}
	previous.eventIDs[input.EventID] = struct{}{}
	previous.sequence = input.Sequence
	// Two consecutive accurate fixes outside the rectangular demo area.
	// Production needs polygon boundaries, uncertainty distance and dwell time.
	outside := point.Latitude < -6.38 || point.Latitude > -6.05 || point.Longitude < 106.68 || point.Longitude > 106.98
	if point.AccuracyM <= 50 && outside {
		if previous.outsideCount < 2 {
			previous.outsideCount++
		}
	} else {
		previous.outsideCount = 0
	}
	inBreach := previous.outsideCount >= 2
	speeding := point.SpeedKph > device.speedLimitKph && point.AccuracyM <= 50
	result := Accepted{Mode: "demo", Accepted: true, VehicleID: device.vehicleID, EventID: input.EventID, Alerts: []Alert{}}
	emit := func(kind, title, description, severity string) {
		alert := Alert{ID: newID(), VehicleID: device.vehicleID, Type: kind, Title: title, Description: description, Severity: severity, CreatedAt: point.ReceivedAt, Status: "open", Source: "simulator", EvidenceEventID: input.EventID}
		tenant.alerts.Append(alert)
		result.Alerts = append(result.Alerts, alert)
	}
	if speeding && !previous.speeding {
		emit("overspeed", "Batas kecepatan armada terlampaui", strconv.FormatFloat(point.SpeedKph, 'f', -1, 64)+" km/jam; kebijakan unit 80 km/jam. Verifikasi konteks jalan.", "medium")
	}
	if inBreach && !previous.inBreach {
		emit("geofence_exit", "Unit keluar wilayah operasi simulasi", "Dua posisi akurat di luar batas Jakarta simulasi. Tinjau posisi dan hubungi pengemudi.", "high")
	}
	previous.speeding = speeding
	previous.inBreach = inBreach
	vehicle.Location = Location{point.Latitude, point.Longitude, "Lokasi dari simulator"}
	vehicle.SpeedKph = point.SpeedKph
	vehicle.Ignition = *input.Ignition
	vehicle.Status = "parked"
	if *input.Ignition {
		vehicle.Status = "idle"
	}
	if point.SpeedKph > 3 {
		vehicle.Status = "moving"
	}
	vehicle.LastSeenAt = point.ReceivedAt
	vehicle.LastPositionAt = input.RecordedAt
	vehicle.Signal = "good"
	if point.AccuracyM > 50 {
		vehicle.Signal = "weak"
	}
	vehicle.Source = "simulator"
	vehicle.BatteryPercent = point.BatteryPercent
	vehicle.FuelPercent = point.FuelPercent
	vehicle.EnergyAt = nil
	if point.BatteryPercent != nil || point.FuelPercent != nil {
		vehicle.EnergyAt = pointer(input.RecordedAt)
	}
	vehicle.RangeKm = nil // Do not retain an invented fixture range after actual simulator data.
	if input.OdometerKm != nil {
		vehicle.OdometerKm = *input.OdometerKm
	}
	tenant.vehicles[device.vehicleID] = vehicle
	if problem := s.commitLocked(before); problem != nil {
		return Accepted{}, problem
	}
	return result, nil
}

func (s *Store) Drivers(tenantID string) []Driver {
	s.mu.RLock()
	defer s.mu.RUnlock()
	result := []Driver{}
	if tenant := s.tenants[tenantID]; tenant != nil {
		for _, driver := range tenant.drivers {
			result = append(result, driver)
		}
	}
	sort.Slice(result, func(i, j int) bool { return result[i].ID < result[j].ID })
	return result
}

func (s *Store) Audit(tenantID string) []AuditEvent {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if tenant := s.tenants[tenantID]; tenant != nil {
		return tenant.audit.Values()
	}
	return []AuditEvent{}
}

func (s *Store) Acknowledge(tenantID, alertID string) (Alert, *APIError) {
	s.mu.Lock()
	defer s.mu.Unlock()
	tenant := s.tenants[tenantID]
	if tenant == nil {
		return Alert{}, fail(404, "not_found", "Alert tidak ditemukan.")
	}
	alerts := tenant.alerts.Values()
	for index, alert := range alerts {
		if alert.ID != alertID {
			continue
		}
		if alert.Status == "acknowledged" {
			return alert, nil
		}
		before := s.backupLocked()
		alert.Status = "acknowledged"
		alerts[index] = alert
		tenant.alerts = NewRing[Alert](MaxAlerts)
		for _, a := range alerts {
			tenant.alerts.Append(a)
		}
		tenant.audit.Append(AuditEvent{ID: newID(), Action: "alert.acknowledged", VehicleID: alert.VehicleID, AlertID: alert.ID, Actor: "demo-operator", CreatedAt: iso(s.clock())})
		if problem := s.commitLocked(before); problem != nil {
			return Alert{}, problem
		}
		return alert, nil
	}
	return Alert{}, fail(404, "not_found", "Alert tidak ditemukan.")
}

func (s *Store) Assign(tenantID, vehicleID, driverID string) (Vehicle, Assignment, *APIError) {
	s.mu.Lock()
	defer s.mu.Unlock()
	tenant := s.tenants[tenantID]
	if tenant == nil {
		return Vehicle{}, Assignment{}, fail(404, "not_found", "Unit tidak ditemukan.")
	}
	vehicle, exists := tenant.vehicles[vehicleID]
	if !exists {
		return Vehicle{}, Assignment{}, fail(404, "not_found", "Unit tidak ditemukan.")
	}
	driver, exists := tenant.drivers[driverID]
	if !exists {
		return Vehicle{}, Assignment{}, fail(404, "not_found", "Pengemudi tidak ditemukan.")
	}
	for _, other := range tenant.vehicles {
		if other.ID != vehicleID && other.Driver.ID == driverID {
			return Vehicle{}, Assignment{}, fail(409, "driver_already_assigned", "Pengemudi masih bertugas di unit lain.")
		}
	}
	before := s.backupLocked()
	assignment := Assignment{ID: newID(), VehicleID: vehicleID, DriverID: driverID, AssignedAt: iso(s.clock())}
	vehicle.Driver = driver
	tenant.vehicles[vehicleID] = vehicle
	tenant.assignments.Append(assignment)
	tenant.audit.Append(AuditEvent{ID: newID(), Action: "driver.assigned", VehicleID: vehicleID, DriverID: driverID, Actor: "demo-operator", CreatedAt: assignment.AssignedAt})
	if problem := s.commitLocked(before); problem != nil {
		return Vehicle{}, Assignment{}, problem
	}
	return s.current(vehicle), assignment, nil
}
