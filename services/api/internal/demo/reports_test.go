package demo

import (
	"encoding/csv"
	"encoding/json"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestReportTenantIsolationUnknownEnergyAndRentalWindows(t *testing.T) {
	store, handler := setup(t)
	response := request(handler, "GET", "/v1/reports/summary?tenantId=tenant-other", userToken, nil, "")
	mustStatus(t, response, 200)
	var report ReportSummary
	if err := json.Unmarshal(response.Body.Bytes(), &report); err != nil {
		t.Fatal(err)
	}
	if report.Fleet.Total != 5 || report.Fleet.Offline != 1 || report.Fleet.Charging != 1 || report.Fleet.Alerts != 3 || report.TelemetrySamples != 90 {
		t.Fatalf("unexpected fixture report: %+v", report)
	}
	mustStatus(t, request(handler, "GET", "/v1/reports/summary", deviceToken, nil, ""), 403)
	mustStatus(t, request(handler, "GET", "/v1/reports/summary", "", nil, ""), 401)
	other := store.Report("tenant-other")
	if other.Fleet.Total != 1 || other.Vehicles[0].VehicleID != "veh-other" {
		t.Fatal("report leaked tenant")
	}
	input := packet()
	input.BatteryPercent = nil
	if _, problem := store.Ingest(devicePrincipal, input); problem != nil {
		t.Fatal(problem)
	}
	unit := store.Report("tenant-demo").Vehicles[0]
	if unit.LastEnergyPercent != nil || unit.SimulatorSamples != 1 || unit.FixtureSamples != 18 || unit.Samples != 19 {
		t.Fatal("unknown or sample provenance was lost", unit)
	}
	active, problem := store.CreateBooking("tenant-demo", bookingInput())
	if problem != nil {
		t.Fatal(problem)
	}
	future := bookingInput()
	future.VehicleID = "veh-002"
	future.StartAt = iso(testNow.Add(time.Hour))
	future.EndAt = iso(testNow.Add(2 * time.Hour))
	if _, problem := store.CreateBooking("tenant-demo", future); problem != nil {
		t.Fatal(problem)
	}
	past := bookingInput()
	past.VehicleID = "veh-003"
	past.StartAt = iso(testNow.Add(-48 * time.Hour))
	past.EndAt = iso(testNow.Add(-time.Minute))
	if _, problem := store.CreateBooking("tenant-demo", past); problem != nil {
		t.Fatal(problem)
	}
	if _, problem := store.CreateWorkOrder("tenant-demo", WorkOrderInput{VehicleID: "veh-005", Title: "Periksa sensor"}); problem != nil {
		t.Fatal(problem)
	}
	report = store.Report("tenant-demo")
	if report.Rental.Active != 1 || report.Rental.Upcoming != 1 || report.Rental.Overdue != 1 || report.Maintenance.Open != 1 {
		t.Fatal("incorrect business report", report)
	}
	if _, problem := store.ReturnBooking("tenant-demo", active.ID); problem != nil {
		t.Fatal(problem)
	}
	if report := store.Report("tenant-demo"); report.Rental.Active != 0 || report.Rental.Returned != 1 {
		t.Fatal("report did not reflect mutation")
	}
}

func TestTelemetryCSVAuthIsolationAndSpreadsheetEscaping(t *testing.T) {
	store, handler := setup(t)
	mustStatus(t, request(handler, "GET", "/v1/reports/telemetry.csv", "", nil, ""), 401)
	mustStatus(t, request(handler, "GET", "/v1/reports/telemetry.csv", deviceToken, nil, ""), 403)
	vehicle := store.tenants["tenant-demo"].vehicles["veh-001"]
	vehicle.Plate = "  =HYPERLINK(\"https://example.invalid\")"
	store.tenants["tenant-demo"].vehicles[vehicle.ID] = vehicle
	input := packet()
	input.BatteryPercent = nil
	if _, problem := store.Ingest(devicePrincipal, input); problem != nil {
		t.Fatal(problem)
	}
	response := request(handler, "GET", "/v1/reports/telemetry.csv?tenantId=tenant-other", userToken, nil, "")
	mustStatus(t, response, 200)
	if response.Header().Get("Content-Type") != "text/csv; charset=utf-8" || !strings.Contains(response.Header().Get("Content-Disposition"), "attachment") {
		t.Fatal("CSV headers incorrect")
	}
	rows, err := csv.NewReader(response.Body).ReadAll()
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 92 || rows[1][1] != "veh-001" || rows[1][2][0] != '\'' || !strings.HasPrefix(rows[1][5], "-6") {
		t.Fatal("bad CSV bounds, formula protection or numeric coordinates")
	}
	if rows[19][9] != "" || rows[19][4] != "simulator" {
		t.Fatal("unknown energy must be empty")
	}
	for _, row := range rows {
		if row[1] == "veh-other" || strings.Contains(strings.Join(row, ","), userToken) {
			t.Fatal("CSV leaked tenant or credentials")
		}
	}
	other := request(handler, "GET", "/v1/reports/telemetry.csv", otherToken, nil, "")
	otherRows, err := csv.NewReader(other.Body).ReadAll()
	if err != nil || len(otherRows) != 19 || otherRows[1][1] != "veh-other" {
		t.Fatal("wrong other-tenant export")
	}
}

func TestEndpointCapsIncludeTrailingBytesAndPreserveState(t *testing.T) {
	store, handler := setup(t)
	encoded, _ := json.Marshal(packet())
	for _, test := range []struct{ path, token, body string }{
		{"/v1/telemetry", deviceToken, string(encoded) + strings.Repeat(" ", 20000)},
		{"/v1/bookings", userToken, `{"customerName":"` + strings.Repeat("x", 5000) + `"}`},
		{"/v1/work-orders", userToken, `{"title":"` + strings.Repeat("x", 5000) + `"}`},
		{"/v1/vehicles/veh-001/assignment", userToken, `{"driverId":"` + strings.Repeat("x", 2000) + `"}`},
	} {
		req := httptest.NewRequest("POST", test.path, strings.NewReader(test.body))
		req.Header.Set("Authorization", "Bearer "+test.token)
		req.Header.Set("Content-Type", "application/json")
		recorder := httptest.NewRecorder()
		handler.ServeHTTP(recorder, req)
		mustStatus(t, recorder, 413)
	}
	if len(store.Bookings("tenant-demo")) != 0 || len(store.Audit("tenant-demo")) != 0 || store.Report("tenant-demo").TelemetrySamples != 90 {
		t.Fatal("oversized request mutated store")
	}
}
