package demo

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"
)

// Optional single-process demo persistence. It contains location and driver data:
// keep it outside Git. This is not a database, encrypted store or audit ledger.
type snapshotTenant struct {
	Vehicles    map[string]Vehicle   `json:"vehicles"`
	Points      map[string][]Point   `json:"points"`
	Alerts      []Alert              `json:"alerts"`
	Drivers     map[string]Driver    `json:"drivers"`
	Audit       []AuditEvent         `json:"audit"`
	Assignments []Assignment         `json:"assignments"`
	Bookings    map[string]Booking   `json:"bookings,omitempty"`
	WorkOrders  map[string]WorkOrder `json:"workOrders,omitempty"`
}
type snapshotCursor struct {
	Sequence     int64    `json:"sequence"`
	EventIDs     []string `json:"eventIds"`
	OutsideCount int      `json:"outsideCount"`
	InBreach     bool     `json:"inBreach"`
	Speeding     bool     `json:"speeding"`
}
type snapshot struct {
	Version int                       `json:"version"`
	Tenants map[string]snapshotTenant `json:"tenants"`
	Cursors map[string]snapshotCursor `json:"cursors"`
}

func OpenStore(clock func() time.Time, path string) (*Store, error) {
	s := NewStore(clock)
	if path == "" {
		return s, nil
	}
	s.dataFile = path
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		if err := s.writeLocked(); err != nil {
			return nil, err
		}
		return s, nil
	}
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() || info.Size() > 16*1024*1024 {
		return nil, errors.New("snapshot must be a regular file <=16 MiB")
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	decoder := json.NewDecoder(io.LimitReader(file, 16*1024*1024))
	decoder.DisallowUnknownFields()
	var data snapshot
	if err := decoder.Decode(&data); err != nil {
		return nil, fmt.Errorf("invalid snapshot: %w", err)
	}
	if decoder.Decode(&struct{}{}) != io.EOF {
		return nil, errors.New("trailing snapshot data")
	}
	if data.Version != 1 || len(data.Tenants) != 2 || len(data.Cursors) > 2 {
		return nil, errors.New("unsupported snapshot version or tenant/device count")
	}
	for id, tenant := range data.Tenants {
		expected := s.tenants[id]
		if expected == nil || len(tenant.Vehicles) != len(expected.vehicles) || len(tenant.Points) != len(expected.points) || len(tenant.Drivers) != len(expected.drivers) || len(tenant.Alerts) > MaxAlerts || len(tenant.Audit) > 500 || len(tenant.Assignments) > 500 || len(tenant.Bookings) > MaxBusinessRecords || len(tenant.WorkOrders) > MaxBusinessRecords {
			return nil, errors.New("invalid snapshot tenant contents")
		}
		for vehicleID, vehicle := range tenant.Vehicles {
			if _, ok := expected.vehicles[vehicleID]; !ok || vehicle.ID != vehicleID {
				return nil, errors.New("unexpected snapshot vehicle")
			}
			if _, err := time.Parse(isoLayout, vehicle.LastPositionAt); err != nil {
				return nil, errors.New("invalid snapshot timestamp")
			}
			if _, ok := tenant.Points[vehicleID]; !ok || len(tenant.Points[vehicleID]) > MaxPoints {
				return nil, errors.New("invalid snapshot history")
			}
		}
		for driverID := range tenant.Drivers {
			if _, ok := expected.drivers[driverID]; !ok {
				return nil, errors.New("unexpected snapshot driver")
			}
		}
		for id, booking := range tenant.Bookings {
			if _, ok := tenant.Vehicles[booking.VehicleID]; !ok || booking.ID != id || (booking.Status != "booked" && booking.Status != "returned") {
				return nil, errors.New("invalid snapshot booking")
			}
			start, firstErr := time.Parse(isoLayout, booking.StartAt)
			end, secondErr := time.Parse(isoLayout, booking.EndAt)
			if firstErr != nil || secondErr != nil || !end.After(start) || !validLabel(booking.CustomerName, 120) {
				return nil, errors.New("invalid snapshot booking interval or customer")
			}
		}
		for id, order := range tenant.WorkOrders {
			if _, ok := tenant.Vehicles[order.VehicleID]; !ok || order.ID != id || (order.Status != "open" && order.Status != "completed") {
				return nil, errors.New("invalid snapshot work order")
			}
			if !validLabel(order.Title, 200) {
				return nil, errors.New("invalid snapshot work order title")
			}
		}
	}
	for id, c := range data.Cursors {
		if _, ok := s.devices[id]; !ok || len(c.EventIDs) > MaxPoints || c.Sequence < 1 {
			return nil, errors.New("invalid snapshot replay cursor")
		}
	}
	s.restoreLocked(data)
	return s, nil
}

func (s *Store) snapshotLocked() snapshot {
	data := snapshot{Version: 1, Tenants: make(map[string]snapshotTenant), Cursors: make(map[string]snapshotCursor)}
	for id, tenant := range s.tenants {
		t := snapshotTenant{Vehicles: make(map[string]Vehicle), Points: make(map[string][]Point), Alerts: tenant.alerts.Values(), Drivers: make(map[string]Driver), Audit: tenant.audit.Values(), Assignments: tenant.assignments.Values(), Bookings: make(map[string]Booking), WorkOrders: make(map[string]WorkOrder)}
		for id, v := range tenant.vehicles {
			t.Vehicles[id] = v
		}
		for id, p := range tenant.points {
			t.Points[id] = p.Values()
		}
		for id, d := range tenant.drivers {
			t.Drivers[id] = d
		}
		for id, b := range tenant.bookings {
			t.Bookings[id] = b
		}
		for id, o := range tenant.workOrders {
			t.WorkOrders[id] = o
		}
		data.Tenants[id] = t
	}
	for id, c := range s.cursors {
		data.Cursors[id] = snapshotCursor{c.sequence, c.eventOrder.Values(), c.outsideCount, c.inBreach, c.speeding}
	}
	return data
}
func (s *Store) restoreLocked(data snapshot) {
	s.tenants = make(map[string]*tenantData)
	s.cursors = make(map[string]*cursor)
	for id, t := range data.Tenants {
		tenant := &tenantData{vehicles: t.Vehicles, points: make(map[string]*Ring[Point]), drivers: t.Drivers, alerts: NewRing[Alert](MaxAlerts), audit: NewRing[AuditEvent](500), assignments: NewRing[Assignment](500), bookings: t.Bookings, workOrders: t.WorkOrders}
		if tenant.bookings == nil {
			tenant.bookings = make(map[string]Booking)
		}
		if tenant.workOrders == nil {
			tenant.workOrders = make(map[string]WorkOrder)
		}
		for id, values := range t.Points {
			ring := NewRing[Point](MaxPoints)
			for _, p := range values {
				ring.Append(p)
			}
			tenant.points[id] = ring
		}
		for _, a := range t.Alerts {
			tenant.alerts.Append(a)
		}
		for _, a := range t.Audit {
			tenant.audit.Append(a)
		}
		for _, a := range t.Assignments {
			tenant.assignments.Append(a)
		}
		s.tenants[id] = tenant
	}
	for id, value := range data.Cursors {
		c := &cursor{sequence: value.Sequence, eventIDs: make(map[string]struct{}), eventOrder: NewRing[string](MaxPoints), outsideCount: value.OutsideCount, inBreach: value.InBreach, speeding: value.Speeding}
		for _, eventID := range value.EventIDs {
			c.eventIDs[eventID] = struct{}{}
			c.eventOrder.Append(eventID)
		}
		s.cursors[id] = c
	}
}
func (s *Store) backupLocked() snapshot {
	if s.dataFile != "" {
		return s.snapshotLocked()
	}
	return snapshot{}
}
func (s *Store) commitLocked(before snapshot) *APIError {
	if s.dataFile == "" {
		return nil
	}
	if err := s.writeLocked(); err != nil {
		s.restoreLocked(before)
		return fail(500, "persistence_failed", "Perubahan dibatalkan karena snapshot tidak dapat disimpan.")
	}
	return nil
}
func (s *Store) writeLocked() error {
	parent := filepath.Dir(s.dataFile)
	if err := os.MkdirAll(parent, 0700); err != nil {
		return err
	}
	file, err := os.CreateTemp(parent, ".revtrack-snapshot-*")
	if err != nil {
		return err
	}
	name := file.Name()
	defer os.Remove(name)
	if err := json.NewEncoder(file).Encode(s.snapshotLocked()); err != nil {
		file.Close()
		return err
	}
	if err := file.Sync(); err != nil {
		file.Close()
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	return os.Rename(name, s.dataFile)
}
