package demo

import (
	"encoding/csv"
	"io"
	"sort"
	"strconv"
	"strings"
	"time"
)

// Reports describe the retained sample window, not completed trips or verified
// fuel/charging sessions. Unknown sensor values remain null (empty in CSV).
type ReportSummary struct {
	Mode                  string             `json:"mode"`
	GeneratedAt           string             `json:"generatedAt"`
	Scope                 string             `json:"scope"`
	PointsLimitPerVehicle int                `json:"pointsLimitPerVehicle"`
	Fleet                 ReportFleet        `json:"fleet"`
	Rental                RentalSummary      `json:"rental"`
	Maintenance           MaintenanceSummary `json:"maintenance"`
	TelemetrySamples      int                `json:"telemetrySamples"`
	Vehicles              []VehicleReport    `json:"vehicles"`
}
type ReportFleet struct {
	Total    int `json:"total"`
	Moving   int `json:"moving"`
	Idle     int `json:"idle"`
	Parked   int `json:"parked"`
	Charging int `json:"charging"`
	Offline  int `json:"offline"`
	Alerts   int `json:"alerts"`
}
type RentalSummary struct {
	Active   int `json:"active"`
	Upcoming int `json:"upcoming"`
	Overdue  int `json:"overdue"`
	Returned int `json:"returned"`
}
type MaintenanceSummary struct {
	Open      int `json:"open"`
	Completed int `json:"completed"`
}
type VehicleReport struct {
	VehicleID           string   `json:"vehicleId"`
	Plate               string   `json:"plate"`
	Powertrain          string   `json:"powertrain"`
	Status              string   `json:"status"`
	Samples             int      `json:"samples"`
	FixtureSamples      int      `json:"fixtureSamples"`
	SimulatorSamples    int      `json:"simulatorSamples"`
	FirstRecordedAt     *string  `json:"firstRecordedAt"`
	LastRecordedAt      *string  `json:"lastRecordedAt"`
	MaxObservedSpeedKph *float64 `json:"maxObservedSpeedKph"`
	EnergyKind          string   `json:"energyKind"`
	FirstEnergyPercent  *float64 `json:"firstEnergyPercent"`
	LastEnergyPercent   *float64 `json:"lastEnergyPercent"`
}

func (s *Store) Report(tenantID string) ReportSummary {
	s.mu.RLock()
	defer s.mu.RUnlock()
	now := s.clock()
	result := ReportSummary{Mode: "demo", GeneratedAt: iso(now), Scope: "retained_samples", PointsLimitPerVehicle: MaxPoints, Vehicles: []VehicleReport{}}
	tenant := s.tenants[tenantID]
	if tenant == nil {
		return result
	}
	for _, stored := range tenant.vehicles {
		v := s.current(stored)
		result.Fleet.Total++
		switch v.Status {
		case "moving":
			result.Fleet.Moving++
		case "idle":
			result.Fleet.Idle++
		case "parked":
			result.Fleet.Parked++
		case "charging":
			result.Fleet.Charging++
		case "offline":
			result.Fleet.Offline++
		}
		points := tenant.points[v.ID].Values()
		unit := VehicleReport{VehicleID: v.ID, Plate: v.Plate, Powertrain: v.Powertrain, Status: v.Status, Samples: len(points), EnergyKind: "fuel"}
		energy := func(p Point) *float64 { return p.FuelPercent }
		if v.Powertrain == "ev" {
			unit.EnergyKind = "battery"
			energy = func(p Point) *float64 { return p.BatteryPercent }
		}
		if len(points) > 0 {
			unit.FirstRecordedAt = pointer(points[0].RecordedAt)
			unit.LastRecordedAt = pointer(points[len(points)-1].RecordedAt)
			unit.FirstEnergyPercent = energy(points[0])
			unit.LastEnergyPercent = energy(points[len(points)-1])
			maximum := points[0].SpeedKph
			for _, p := range points {
				if p.SpeedKph > maximum {
					maximum = p.SpeedKph
				}
				if p.Source == "fixture" {
					unit.FixtureSamples++
				}
				if p.Source == "simulator" {
					unit.SimulatorSamples++
				}
			}
			unit.MaxObservedSpeedKph = pointer(maximum)
		}
		result.TelemetrySamples += unit.Samples
		result.Vehicles = append(result.Vehicles, unit)
	}
	sort.Slice(result.Vehicles, func(i, j int) bool { return result.Vehicles[i].VehicleID < result.Vehicles[j].VehicleID })
	for _, alert := range tenant.alerts.Values() {
		if alert.Status == "open" {
			result.Fleet.Alerts++
		}
	}
	for _, booking := range tenant.bookings {
		if booking.Status == "returned" {
			result.Rental.Returned++
			continue
		}
		start, _ := time.Parse(isoLayout, booking.StartAt)
		end, _ := time.Parse(isoLayout, booking.EndAt)
		switch {
		case start.After(now):
			result.Rental.Upcoming++
		case !end.After(now):
			result.Rental.Overdue++
		default:
			result.Rental.Active++
		}
	}
	for _, order := range tenant.workOrders {
		if order.Status == "open" {
			result.Maintenance.Open++
		} else {
			result.Maintenance.Completed++
		}
	}
	return result
}

// Protect textual cells from spreadsheet formula interpretation. Numeric cells
// are formatted separately so signed coordinates remain usable as numbers.
func csvText(value string) string {
	trimmed := strings.TrimLeft(value, " \t\r\n")
	if trimmed != "" && strings.ContainsRune("=+-@", rune(trimmed[0])) {
		return "'" + value
	}
	return value
}
func csvNumber(value *float64) string {
	if value == nil {
		return ""
	}
	return strconv.FormatFloat(*value, 'f', -1, 64)
}

func (s *Store) ExportTelemetry(tenantID string, output io.Writer) error {
	// Copy a bounded consistent snapshot before writing to a possibly slow client.
	s.mu.RLock()
	rows := [][]string{{"mode", "vehicle_id", "plate", "recorded_at", "source", "latitude", "longitude", "speed_kph", "accuracy_m", "battery_percent", "fuel_percent", "odometer_km"}}
	if tenant := s.tenants[tenantID]; tenant != nil {
		ids := make([]string, 0, len(tenant.vehicles))
		for id := range tenant.vehicles {
			ids = append(ids, id)
		}
		sort.Strings(ids)
		for _, id := range ids {
			for _, p := range tenant.points[id].Values() {
				rows = append(rows, []string{"demo", csvText(id), csvText(tenant.vehicles[id].Plate), csvText(p.RecordedAt), csvText(p.Source), csvNumber(&p.Latitude), csvNumber(&p.Longitude), csvNumber(&p.SpeedKph), csvNumber(&p.AccuracyM), csvNumber(p.BatteryPercent), csvNumber(p.FuelPercent), csvNumber(p.OdometerKm)})
			}
		}
	}
	s.mu.RUnlock()
	writer := csv.NewWriter(output)
	return writer.WriteAll(rows)
}
