package demo

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

var testNow = time.Date(2026, 10, 2, 3, 0, 0, 0, time.UTC)

const userToken = "test-user-token-12345678901234567890"
const otherToken = "test-other-user-12345678901234567890"
const deviceToken = "test-device-token-12345678901234567890"

var devicePrincipal = Credential{Token: deviceToken, Kind: "device", TenantID: "tenant-demo", DeviceID: "dev-001"}

func packet() TelemetryInput {
	return TelemetryInput{EventID: "event-00001", Sequence: 1, RecordedAt: iso(testNow), Latitude: pointer(-6.2088), Longitude: pointer(106.8229), SpeedKph: pointer(45.0), Ignition: pointer(true), AccuracyM: pointer(8.0), BatteryPercent: pointer(77.0), OdometerKm: pointer(18421.0)}
}
func setup(t *testing.T) (*Store, http.Handler) {
	t.Helper()
	store := NewStore(func() time.Time { return testNow })
	handler, err := NewHandler(store, []Credential{{Token: userToken, Kind: "user", TenantID: "tenant-demo"}, {Token: otherToken, Kind: "user", TenantID: "tenant-other"}, devicePrincipal}, "")
	if err != nil {
		t.Fatal(err)
	}
	return store, handler
}
func request(handler http.Handler, method, path, token string, body any, origin string) *httptest.ResponseRecorder {
	var buffer bytes.Buffer
	if body != nil {
		_ = json.NewEncoder(&buffer).Encode(body)
	}
	req := httptest.NewRequest(method, path, &buffer)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if origin != "" {
		req.Header.Set("Origin", origin)
	}
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	return rec
}
func mustStatus(t *testing.T, result *httptest.ResponseRecorder, status int) {
	t.Helper()
	if result.Code != status {
		t.Fatalf("expected %d got %d: %s", status, result.Code, result.Body.String())
	}
}
func mustCode(t *testing.T, err *APIError, code string) {
	t.Helper()
	if err == nil || err.Code != code {
		t.Fatalf("expected error %s got %#v", code, err)
	}
}

func TestAuthAndTenantIsolation(t *testing.T) {
	_, h := setup(t)
	mustStatus(t, request(h, "GET", "/v1/fleet", "", nil, ""), 401)
	mustStatus(t, request(h, "GET", "/v1/fleet", deviceToken, nil, ""), 403)
	result := request(h, "GET", "/v1/fleet?tenantId=tenant-other", userToken, nil, "")
	mustStatus(t, result, 200)
	var fleet Fleet
	if err := json.Unmarshal(result.Body.Bytes(), &fleet); err != nil {
		t.Fatal(err)
	}
	if len(fleet.Vehicles) != 5 {
		t.Fatal("wrong tenant fleet size")
	}
	for _, path := range []string{"/v1/vehicles/veh-other", "/v1/vehicles/veh-other/telemetry"} {
		mustStatus(t, request(h, "GET", path, userToken, nil, ""), 404)
	}
	other := request(h, "GET", "/v1/fleet", otherToken, nil, "")
	_ = json.Unmarshal(other.Body.Bytes(), &fleet)
	if len(fleet.Vehicles) != 1 || fleet.Vehicles[0].ID != "veh-other" {
		t.Fatal("other tenant leaked")
	}
}

func TestDeviceIdentityAndStrictPayload(t *testing.T) {
	store, h := setup(t)
	mustStatus(t, request(h, "POST", "/v1/telemetry", userToken, packet(), ""), 403)
	for _, field := range []string{"tenantId", "vehicleId", "deviceId"} {
		encoded, _ := json.Marshal(packet())
		data := map[string]any{}
		_ = json.Unmarshal(encoded, &data)
		data[field] = "veh-other"
		mustStatus(t, request(h, "POST", "/v1/telemetry", deviceToken, data, ""), 422)
	}
	mustStatus(t, request(h, "POST", "/v1/telemetry", deviceToken, packet(), ""), 202)
	v, _ := store.Vehicle("tenant-demo", "veh-001")
	if *v.BatteryPercent != 77 || v.Source != "simulator" {
		t.Fatal("accepted measurement missing")
	}
	v, _ = store.Vehicle("tenant-other", "veh-other")
	if *v.BatteryPercent != 78 {
		t.Fatal("cross-tenant write")
	}
}

func TestReplayAndLatePackets(t *testing.T) {
	store, _ := setup(t)
	input := packet()
	if _, err := store.Ingest(devicePrincipal, input); err != nil {
		t.Fatal(err)
	}
	_, err := store.Ingest(devicePrincipal, input)
	mustCode(t, err, "replayed_event")
	input.EventID = "event-00002"
	input.Sequence = 2
	input.RecordedAt = iso(testNow.Add(-time.Second))
	input.Latitude = pointer(-7.0)
	_, err = store.Ingest(devicePrincipal, input)
	mustCode(t, err, "out_of_order")
	v, _ := store.Vehicle("tenant-demo", "veh-001")
	if v.Location.Latitude != -6.2088 {
		t.Fatal("latest location rolled backward")
	}
	input.RecordedAt = iso(testNow.Add(time.Second))
	if _, err := store.Ingest(devicePrincipal, input); err != nil {
		t.Fatal("rejected packet consumed sequence", err)
	}
}

func TestValidationDoesNotMutateState(t *testing.T) {
	store, _ := setup(t)
	mutations := []func(*TelemetryInput){
		func(p *TelemetryInput) { p.Latitude = pointer(91.0) }, func(p *TelemetryInput) { p.Longitude = pointer(-181.0) }, func(p *TelemetryInput) { p.SpeedKph = pointer(-1.0) },
		func(p *TelemetryInput) { p.Latitude = nil }, func(p *TelemetryInput) { p.Ignition = nil }, func(p *TelemetryInput) { p.Sequence = 0 }, func(p *TelemetryInput) { p.AccuracyM = pointer(-1.0) },
		func(p *TelemetryInput) { p.BatteryPercent = pointer(101.0) }, func(p *TelemetryInput) { p.RecordedAt = "2026-02-30T03:00:00.000Z" },
		func(p *TelemetryInput) { p.RecordedAt = iso(testNow.Add(31 * time.Second)) }, func(p *TelemetryInput) { p.RecordedAt = iso(testNow.Add(-25 * time.Hour)) },
		func(p *TelemetryInput) { p.FuelPercent = pointer(30.0) }, func(p *TelemetryInput) { p.OdometerKm = pointer(0.0) },
	}
	for index, mutate := range mutations {
		input := packet()
		mutate(&input)
		if _, err := store.Ingest(devicePrincipal, input); err == nil || err.Status != 422 {
			t.Fatalf("mutation %d should fail: %v", index, err)
		}
	}
	points, _ := store.Telemetry("tenant-demo", "veh-001")
	if len(points) != 18 {
		t.Fatal("invalid writes mutated history")
	}
	badPrincipal := devicePrincipal
	badPrincipal.TenantID = "tenant-other"
	_, err := store.Ingest(badPrincipal, packet())
	mustCode(t, err, "device_unassigned")
}

func TestGeofenceAndSpeedTransitions(t *testing.T) {
	store, _ := setup(t)
	send := func(sequence int64, latitude, accuracy, speed float64) Accepted {
		input := packet()
		input.Sequence = sequence
		input.EventID = newID()
		input.RecordedAt = iso(testNow.Add(time.Duration(sequence) * time.Millisecond))
		input.Latitude = pointer(latitude)
		input.AccuracyM = pointer(accuracy)
		input.SpeedKph = pointer(speed)
		accepted, err := store.Ingest(devicePrincipal, input)
		if err != nil {
			t.Fatal(err)
		}
		return accepted
	}
	if len(send(1, -7, 900, 45).Alerts) != 0 || len(send(2, -7, 8, 45).Alerts) != 0 {
		t.Fatal("uncertain or single point triggered geofence")
	}
	if result := send(3, -7, 8, 90); len(result.Alerts) != 2 {
		t.Fatalf("want geofence and speed events: %+v", result)
	}
	if len(send(4, -7, 8, 90).Alerts) != 0 {
		t.Fatal("duplicate alert storm")
	}
	if len(store.Alerts("tenant-other")) != 0 {
		t.Fatal("cross-tenant alert")
	}
}

func TestStorageBoundsAndConcurrentReplay(t *testing.T) {
	store, _ := setup(t)
	var accepted atomic.Int32
	var wg sync.WaitGroup
	for range 20 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, err := store.Ingest(devicePrincipal, packet()); err == nil {
				accepted.Add(1)
			}
			_ = store.Fleet("tenant-demo")
		}()
	}
	wg.Wait()
	if accepted.Load() != 1 {
		t.Fatal("concurrent duplicates accepted", accepted.Load())
	}
	for i := int64(2); i <= 700; i++ {
		input := packet()
		input.EventID = newID()
		input.Sequence = i
		input.RecordedAt = iso(testNow.Add(time.Duration(i) * time.Millisecond))
		input.SpeedKph = pointer(40.0 + float64(i%2)*50)
		if _, err := store.Ingest(devicePrincipal, input); err != nil {
			t.Fatal(err)
		}
	}
	points, _ := store.Telemetry("tenant-demo", "veh-001")
	if len(points) != MaxPoints || len(store.Alerts("tenant-demo")) != MaxAlerts {
		t.Fatal("buffers exceeded bounds")
	}
	_, err := store.Ingest(devicePrincipal, packet())
	mustCode(t, err, "replayed_event")
}

func TestNoHardwareAndExactCORS(t *testing.T) {
	_, h := setup(t)
	result := request(h, "GET", "/health", "", nil, "")
	mustStatus(t, result, 200)
	if !strings.Contains(result.Body.String(), `"hardwareCommands":false`) {
		t.Fatal("missing simulation status")
	}
	for _, command := range []string{"immobilize", "call"} {
		mustStatus(t, request(h, "POST", "/v1/vehicles/veh-001/"+command, userToken, nil, ""), 404)
	}
	result = request(h, "GET", "/v1/fleet", userToken, nil, "http://127.0.0.1:7357")
	mustStatus(t, result, 200)
	if result.Header().Get("Access-Control-Allow-Origin") != "http://127.0.0.1:7357" {
		t.Fatal("missing exact origin")
	}
	mustStatus(t, request(h, "GET", "/v1/fleet", userToken, nil, "https://attacker.invalid"), 403)
}

func TestMissingEnergyStaysUnknown(t *testing.T) {
	store, _ := setup(t)
	input := packet()
	input.BatteryPercent = nil
	if _, err := store.Ingest(devicePrincipal, input); err != nil {
		t.Fatal(err)
	}
	v, _ := store.Vehicle("tenant-demo", "veh-001")
	if v.BatteryPercent != nil || v.EnergyAt != nil || v.RangeKm != nil {
		t.Fatal("fabricated energy")
	}
}

func TestAcknowledgeAssignmentAuditAndTenantWrites(t *testing.T) {
	store, h := setup(t)
	mustStatus(t, request(h, "POST", "/v1/alerts/alert-001/acknowledge", otherToken, nil, ""), 404)
	mustStatus(t, request(h, "POST", "/v1/alerts/alert-001/acknowledge", deviceToken, nil, ""), 403)
	for range 2 {
		mustStatus(t, request(h, "POST", "/v1/alerts/alert-001/acknowledge", userToken, map[string]any{}, ""), 200)
	}
	if len(store.Audit("tenant-demo")) != 1 {
		t.Fatal("acknowledgement must be idempotent")
	}
	mustStatus(t, request(h, "POST", "/v1/vehicles/veh-other/assignment", userToken, map[string]string{"driverId": "drv-006"}, ""), 404)
	mustStatus(t, request(h, "POST", "/v1/vehicles/veh-001/assignment", userToken, map[string]string{"driverId": "drv-002"}, ""), 409)
	mustStatus(t, request(h, "POST", "/v1/vehicles/veh-001/assignment", userToken, map[string]string{"driverId": "drv-006"}, ""), 200)
	v, _ := store.Vehicle("tenant-demo", "veh-001")
	if v.Driver.ID != "drv-006" || len(store.Audit("tenant-demo")) != 2 {
		t.Fatal("assignment/audit missing")
	}
	if len(store.Drivers("tenant-demo")) != 6 || len(store.Audit("tenant-other")) != 0 {
		t.Fatal("driver/audit tenant leak")
	}
}

func TestPersistenceRestartAndWriteFailureRollback(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state.json")
	clock := func() time.Time { return testNow }
	store, err := OpenStore(clock, path)
	if err != nil {
		t.Fatal(err)
	}
	if _, problem := store.Ingest(devicePrincipal, packet()); problem != nil {
		t.Fatal(problem)
	}
	if _, problem := store.Acknowledge("tenant-demo", "alert-001"); problem != nil {
		t.Fatal(problem)
	}
	if _, _, problem := store.Assign("tenant-demo", "veh-001", "drv-006"); problem != nil {
		t.Fatal(problem)
	}
	reopened, err := OpenStore(clock, path)
	if err != nil {
		t.Fatal(err)
	}
	v, _ := reopened.Vehicle("tenant-demo", "veh-001")
	if v.Driver.ID != "drv-006" || *v.BatteryPercent != 77 || len(reopened.Audit("tenant-demo")) != 2 {
		t.Fatal("restart lost state")
	}
	_, problem := reopened.Ingest(devicePrincipal, packet())
	mustCode(t, problem, "replayed_event")
	info, _ := os.Stat(path)
	if info.Mode().Perm() != 0600 {
		t.Fatal("snapshot should be private")
	}
	reopened.dataFile = filepath.Join(path, "impossible.json")
	_, problem = reopened.Acknowledge("tenant-demo", "alert-002")
	mustCode(t, problem, "persistence_failed")
	if len(reopened.Audit("tenant-demo")) != 2 {
		t.Fatal("failed persistence did not roll back audit")
	}
	for _, a := range reopened.Alerts("tenant-demo") {
		if a.ID == "alert-002" && a.Status != "open" {
			t.Fatal("failed persistence mutated alert")
		}
	}
}

func TestOversizeAndMalformedBodies(t *testing.T) {
	_, h := setup(t)
	for _, body := range []string{`null`, `{"speedKph":"fast"}`, `{} {}`, `[]`} {
		req := httptest.NewRequest("POST", "/v1/telemetry", strings.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+deviceToken)
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		mustStatus(t, rec, 422)
	}
	req := httptest.NewRequest("POST", "/v1/telemetry", strings.NewReader(`{"eventId":"`+strings.Repeat("x", 20000)+`"}`))
	req.Header.Set("Authorization", "Bearer "+deviceToken)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	mustStatus(t, rec, 413)
}

func TestCredentialsMustBeDistinct(t *testing.T) {
	store, _ := setup(t)
	_, err := NewHandler(store, []Credential{{Token: userToken, Kind: "user", TenantID: "a"}, {Token: userToken, Kind: "device", TenantID: "a"}}, "")
	if err == nil {
		t.Fatal("shared token accepted")
	}
}
