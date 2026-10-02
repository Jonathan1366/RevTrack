package demo

import (
	"encoding/json"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func bookingInput() BookingInput {
	return BookingInput{VehicleID: "veh-001", CustomerName: "Pelanggan Simulasi", StartAt: iso(testNow.Add(-time.Minute)), EndAt: iso(testNow.Add(24 * time.Hour))}
}

func TestBookingOverlapConcurrentAndIntervalValidation(t *testing.T) {
	store, _ := setup(t)
	var accepted atomic.Int32
	var wg sync.WaitGroup
	for range 20 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, problem := store.CreateBooking("tenant-demo", bookingInput()); problem == nil {
				accepted.Add(1)
			}
		}()
	}
	wg.Wait()
	if accepted.Load() != 1 || len(store.Bookings("tenant-demo")) != 1 {
		t.Fatal("overlapping concurrent booking accepted")
	}
	_, problem := store.CreateBooking("tenant-demo", bookingInput())
	mustCode(t, problem, "booking_overlap")
	adjacent := bookingInput()
	adjacent.StartAt = adjacent.EndAt
	adjacent.EndAt = iso(testNow.Add(48 * time.Hour))
	if _, problem := store.CreateBooking("tenant-demo", adjacent); problem != nil {
		t.Fatal("adjacent [start,end) interval rejected", problem)
	}
	for _, mutate := range []func(*BookingInput){
		func(p *BookingInput) { p.StartAt = "yesterday" }, func(p *BookingInput) { p.EndAt = p.StartAt }, func(p *BookingInput) { p.CustomerName = "  " },
		func(p *BookingInput) { p.CustomerName = "malformed\nname" }, func(p *BookingInput) { p.EndAt = iso(testNow.Add(400 * 24 * time.Hour)) },
		func(p *BookingInput) { p.StartAt = "2026-10-02T03:00:00.0001Z"; p.EndAt = "2026-10-02T03:00:00.0002Z" },
	} {
		input := bookingInput()
		mutate(&input)
		_, problem := store.CreateBooking("tenant-demo", input)
		mustCode(t, problem, "invalid_booking")
	}
	if len(store.Bookings("tenant-demo")) != 2 {
		t.Fatal("invalid input mutated bookings")
	}
}

func TestRentalReturnMaintenanceAndAvailability(t *testing.T) {
	store, h := setup(t)
	response := request(h, "POST", "/v1/bookings", userToken, bookingInput(), "")
	mustStatus(t, response, 201)
	var payload struct {
		Booking Booking `json:"booking"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	booking := payload.Booking
	mustStatus(t, request(h, "POST", "/v1/bookings/"+booking.ID+"/return", otherToken, nil, ""), 404)
	mustStatus(t, request(h, "POST", "/v1/bookings/"+booking.ID+"/return", deviceToken, nil, ""), 403)
	_, problem := store.CreateWorkOrder("tenant-demo", WorkOrderInput{VehicleID: "veh-001", Title: "Periksa ban"})
	mustCode(t, problem, "vehicle_on_rental")
	for range 2 {
		mustStatus(t, request(h, "POST", "/v1/bookings/"+booking.ID+"/return", userToken, nil, ""), 200)
	}
	if len(store.Audit("tenant-demo")) != 2 {
		t.Fatal("return should be idempotent and audited")
	}
	response = request(h, "POST", "/v1/work-orders", userToken, WorkOrderInput{VehicleID: "veh-001", Title: "Periksa ban"}, "")
	mustStatus(t, response, 201)
	var workPayload struct {
		WorkOrder WorkOrder `json:"workOrder"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &workPayload); err != nil {
		t.Fatal(err)
	}
	_, problem = store.CreateBooking("tenant-demo", bookingInput())
	mustCode(t, problem, "unit_unavailable")
	mustStatus(t, request(h, "POST", "/v1/work-orders/"+workPayload.WorkOrder.ID+"/complete", otherToken, nil, ""), 404)
	for range 2 {
		mustStatus(t, request(h, "POST", "/v1/work-orders/"+workPayload.WorkOrder.ID+"/complete", userToken, nil, ""), 200)
	}
	if len(store.Audit("tenant-demo")) != 4 {
		t.Fatal("completion should be idempotent")
	}
	if _, problem := store.CreateBooking("tenant-demo", bookingInput()); problem != nil {
		t.Fatal("returned vehicle remained unavailable", problem)
	}
	mustStatus(t, request(h, "GET", "/v1/bookings", userToken, nil, ""), 200)
	mustStatus(t, request(h, "GET", "/v1/work-orders", userToken, nil, ""), 200)
}

func TestBusinessTenantIsolationAndFutureReturn(t *testing.T) {
	store, h := setup(t)
	input := bookingInput()
	input.VehicleID = "veh-other"
	mustStatus(t, request(h, "POST", "/v1/bookings", userToken, input, ""), 404)
	mustStatus(t, request(h, "POST", "/v1/work-orders", userToken, WorkOrderInput{VehicleID: "veh-other", Title: "Inspection"}, ""), 404)
	mustStatus(t, request(h, "POST", "/v1/bookings", deviceToken, bookingInput(), ""), 403)
	input = bookingInput()
	input.StartAt = iso(testNow.Add(time.Hour))
	input.EndAt = iso(testNow.Add(2 * time.Hour))
	booking, problem := store.CreateBooking("tenant-demo", input)
	if problem != nil {
		t.Fatal(problem)
	}
	_, problem = store.ReturnBooking("tenant-demo", booking.ID)
	mustCode(t, problem, "booking_not_started")
	if len(store.Bookings("tenant-other")) != 0 || len(store.WorkOrders("tenant-other")) != 0 || len(store.Audit("tenant-other")) != 0 {
		t.Fatal("cross-tenant business data leak")
	}
	_, problem = store.CreateWorkOrder("tenant-demo", WorkOrderInput{VehicleID: "veh-001", Title: " "})
	mustCode(t, problem, "invalid_work_order")
}

func TestBusinessPersistenceAndFailedWriteRollback(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state.json")
	clock := func() time.Time { return testNow }
	store, err := OpenStore(clock, path)
	if err != nil {
		t.Fatal(err)
	}
	booking, problem := store.CreateBooking("tenant-demo", bookingInput())
	if problem != nil {
		t.Fatal(problem)
	}
	order, problem := store.CreateWorkOrder("tenant-demo", WorkOrderInput{VehicleID: "veh-002", Title: "Pemeriksaan charging port"})
	if problem != nil {
		t.Fatal(problem)
	}
	reopened, err := OpenStore(clock, path)
	if err != nil {
		t.Fatal(err)
	}
	if len(reopened.Bookings("tenant-demo")) != 1 || len(reopened.WorkOrders("tenant-demo")) != 1 {
		t.Fatal("restart lost business data")
	}
	_, problem = reopened.CreateBooking("tenant-demo", bookingInput())
	mustCode(t, problem, "booking_overlap")
	reopened.dataFile = filepath.Join(path, "cannot-write.json")
	_, problem = reopened.ReturnBooking("tenant-demo", booking.ID)
	mustCode(t, problem, "persistence_failed")
	_, problem = reopened.CompleteWorkOrder("tenant-demo", order.ID)
	mustCode(t, problem, "persistence_failed")
	if reopened.Bookings("tenant-demo")[0].Status != "booked" || reopened.WorkOrders("tenant-demo")[0].Status != "open" || len(reopened.Audit("tenant-demo")) != 2 {
		t.Fatal("failed business persistence mutated state")
	}
}

func TestBusinessCapacityNeverEvictsReservations(t *testing.T) {
	store, _ := setup(t)
	for range MaxBusinessRecords {
		id := newID()
		store.tenants["tenant-demo"].bookings[id] = Booking{ID: id, Status: "booked"}
	}
	_, problem := store.CreateBooking("tenant-demo", bookingInput())
	mustCode(t, problem, "demo_capacity")
	if len(store.Bookings("tenant-demo")) != MaxBusinessRecords {
		t.Fatal("active reservations evicted")
	}
}
