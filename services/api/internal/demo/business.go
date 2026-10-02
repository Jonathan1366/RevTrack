package demo

import (
	"sort"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"
)

// Active reservations are never evicted: a full demo collection rejects new writes.
const MaxBusinessRecords = 500

func validLabel(value string, max int) bool {
	if value == "" || !utf8.ValidString(value) || utf8.RuneCountInString(value) > max {
		return false
	}
	for _, r := range value {
		if unicode.IsControl(r) {
			return false
		}
	}
	return true
}

func (s *Store) Bookings(tenantID string) []Booking {
	s.mu.RLock()
	defer s.mu.RUnlock()
	result := []Booking{}
	if tenant := s.tenants[tenantID]; tenant != nil {
		for _, booking := range tenant.bookings {
			result = append(result, booking)
		}
	}
	sort.Slice(result, func(i, j int) bool {
		if result[i].CreatedAt == result[j].CreatedAt {
			return result[i].ID < result[j].ID
		}
		return result[i].CreatedAt > result[j].CreatedAt
	})
	return result
}

func (s *Store) CreateBooking(tenantID string, input BookingInput) (Booking, *APIError) {
	s.mu.Lock()
	defer s.mu.Unlock()
	tenant := s.tenants[tenantID]
	if tenant == nil {
		return Booking{}, fail(404, "not_found", "Unit tidak ditemukan.")
	}
	if _, exists := tenant.vehicles[input.VehicleID]; !exists {
		return Booking{}, fail(404, "not_found", "Unit tidak ditemukan.")
	}
	input.CustomerName = strings.TrimSpace(input.CustomerName)
	if !validLabel(input.CustomerName, 120) {
		return Booking{}, fail(422, "invalid_booking", "customerName wajib 1–120 karakter tanpa karakter kontrol.")
	}
	start, err := time.Parse(time.RFC3339Nano, input.StartAt)
	if err != nil {
		return Booking{}, fail(422, "invalid_booking", "startAt harus ISO timestamp dengan timezone.")
	}
	end, err := time.Parse(time.RFC3339Nano, input.EndAt)
	start = start.Truncate(time.Millisecond)
	end = end.Truncate(time.Millisecond)
	if err != nil || !end.After(start) || end.Sub(start) > 366*24*time.Hour {
		return Booking{}, fail(422, "invalid_booking", "endAt harus setelah startAt, maksimum durasi 366 hari pada demo.")
	}
	if len(tenant.bookings) >= MaxBusinessRecords {
		return Booking{}, fail(409, "demo_capacity", "Kapasitas 500 booking demo tercapai; arsipkan melalui implementasi produksi.")
	}
	for _, order := range tenant.workOrders {
		if order.VehicleID == input.VehicleID && order.Status == "open" {
			return Booking{}, fail(409, "unit_unavailable", "Unit memiliki work order terbuka.")
		}
	}
	for _, existing := range tenant.bookings {
		if existing.VehicleID != input.VehicleID || existing.Status != "booked" {
			continue
		}
		existingStart, _ := time.Parse(isoLayout, existing.StartAt)
		existingEnd, _ := time.Parse(isoLayout, existing.EndAt)
		if start.Before(existingEnd) && end.After(existingStart) {
			return Booking{}, fail(409, "booking_overlap", "Unit sudah dibooking pada interval tersebut.")
		}
		if !existingEnd.After(s.clock()) {
			return Booking{}, fail(409, "return_overdue", "Booking sebelumnya melewati jadwal dan unit belum dikembalikan.")
		}
	}
	before := s.backupLocked()
	booking := Booking{ID: newID(), VehicleID: input.VehicleID, CustomerName: input.CustomerName, StartAt: iso(start), EndAt: iso(end), Status: "booked", CreatedAt: iso(s.clock())}
	tenant.bookings[booking.ID] = booking
	tenant.audit.Append(AuditEvent{ID: newID(), Action: "booking.created", VehicleID: booking.VehicleID, ResourceID: booking.ID, Actor: "demo-operator", CreatedAt: booking.CreatedAt})
	if problem := s.commitLocked(before); problem != nil {
		return Booking{}, problem
	}
	return booking, nil
}

func (s *Store) ReturnBooking(tenantID, bookingID string) (Booking, *APIError) {
	s.mu.Lock()
	defer s.mu.Unlock()
	tenant := s.tenants[tenantID]
	if tenant == nil {
		return Booking{}, fail(404, "not_found", "Booking tidak ditemukan.")
	}
	booking, exists := tenant.bookings[bookingID]
	if !exists {
		return Booking{}, fail(404, "not_found", "Booking tidak ditemukan.")
	}
	if booking.Status == "returned" {
		return booking, nil
	}
	start, _ := time.Parse(isoLayout, booking.StartAt)
	if start.After(s.clock()) {
		return Booking{}, fail(409, "booking_not_started", "Booking masa depan belum bisa dicatat sebagai pengembalian.")
	}
	before := s.backupLocked()
	booking.Status = "returned"
	booking.ReturnedAt = iso(s.clock())
	tenant.bookings[bookingID] = booking
	tenant.audit.Append(AuditEvent{ID: newID(), Action: "booking.returned", VehicleID: booking.VehicleID, ResourceID: booking.ID, Actor: "demo-operator", CreatedAt: booking.ReturnedAt})
	if problem := s.commitLocked(before); problem != nil {
		return Booking{}, problem
	}
	return booking, nil
}

func (s *Store) WorkOrders(tenantID string) []WorkOrder {
	s.mu.RLock()
	defer s.mu.RUnlock()
	result := []WorkOrder{}
	if tenant := s.tenants[tenantID]; tenant != nil {
		for _, order := range tenant.workOrders {
			result = append(result, order)
		}
	}
	sort.Slice(result, func(i, j int) bool {
		if result[i].CreatedAt == result[j].CreatedAt {
			return result[i].ID < result[j].ID
		}
		return result[i].CreatedAt > result[j].CreatedAt
	})
	return result
}

func (s *Store) CreateWorkOrder(tenantID string, input WorkOrderInput) (WorkOrder, *APIError) {
	s.mu.Lock()
	defer s.mu.Unlock()
	tenant := s.tenants[tenantID]
	if tenant == nil {
		return WorkOrder{}, fail(404, "not_found", "Unit tidak ditemukan.")
	}
	if _, exists := tenant.vehicles[input.VehicleID]; !exists {
		return WorkOrder{}, fail(404, "not_found", "Unit tidak ditemukan.")
	}
	input.Title = strings.TrimSpace(input.Title)
	if !validLabel(input.Title, 200) {
		return WorkOrder{}, fail(422, "invalid_work_order", "title wajib 1–200 karakter tanpa karakter kontrol.")
	}
	if len(tenant.workOrders) >= MaxBusinessRecords {
		return WorkOrder{}, fail(409, "demo_capacity", "Kapasitas 500 work order demo tercapai.")
	}
	for _, booking := range tenant.bookings {
		start, _ := time.Parse(isoLayout, booking.StartAt)
		if booking.VehicleID == input.VehicleID && booking.Status == "booked" && !start.After(s.clock()) {
			return WorkOrder{}, fail(409, "vehicle_on_rental", "Unit masih dalam rental; catat pengembalian sebelum pekerjaan bengkel.")
		}
	}
	before := s.backupLocked()
	order := WorkOrder{ID: newID(), VehicleID: input.VehicleID, Title: input.Title, Status: "open", CreatedAt: iso(s.clock())}
	tenant.workOrders[order.ID] = order
	tenant.audit.Append(AuditEvent{ID: newID(), Action: "work_order.created", VehicleID: order.VehicleID, ResourceID: order.ID, Actor: "demo-operator", CreatedAt: order.CreatedAt})
	if problem := s.commitLocked(before); problem != nil {
		return WorkOrder{}, problem
	}
	return order, nil
}

func (s *Store) CompleteWorkOrder(tenantID, orderID string) (WorkOrder, *APIError) {
	s.mu.Lock()
	defer s.mu.Unlock()
	tenant := s.tenants[tenantID]
	if tenant == nil {
		return WorkOrder{}, fail(404, "not_found", "Work order tidak ditemukan.")
	}
	order, exists := tenant.workOrders[orderID]
	if !exists {
		return WorkOrder{}, fail(404, "not_found", "Work order tidak ditemukan.")
	}
	if order.Status == "completed" {
		return order, nil
	}
	before := s.backupLocked()
	order.Status = "completed"
	order.CompletedAt = iso(s.clock())
	tenant.workOrders[orderID] = order
	tenant.audit.Append(AuditEvent{ID: newID(), Action: "work_order.completed", VehicleID: order.VehicleID, ResourceID: order.ID, Actor: "demo-operator", CreatedAt: order.CompletedAt})
	if problem := s.commitLocked(before); problem != nil {
		return WorkOrder{}, problem
	}
	return order, nil
}
