package demo

import (
	"crypto/sha256"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"regexp"
	"strings"
)

var vehicleRoute = regexp.MustCompile(`^/v1/vehicles/([A-Za-z0-9_-]+)(/telemetry)?$`)
var ackRoute = regexp.MustCompile(`^/v1/alerts/([A-Za-z0-9_-]+)/acknowledge$`)
var assignmentRoute = regexp.MustCompile(`^/v1/vehicles/([A-Za-z0-9_-]+)/assignment$`)
var bookingReturnRoute = regexp.MustCompile(`^/v1/bookings/([A-Za-z0-9_-]+)/return$`)
var workOrderCompleteRoute = regexp.MustCompile(`^/v1/work-orders/([A-Za-z0-9_-]+)/complete$`)
var localOrigin = regexp.MustCompile(`^http://(localhost|127\.0\.0\.1):[0-9]+$`)

func decodeBody(w http.ResponseWriter, r *http.Request, target any, limit int64, code, message string) *APIError {
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, limit))
	decoder.DisallowUnknownFields()
	err := decoder.Decode(target)
	if err == nil {
		err = decoder.Decode(&struct{}{})
		if err == io.EOF {
			return nil
		}
	}
	var tooLarge *http.MaxBytesError
	if errors.As(err, &tooLarge) {
		return fail(413, "payload_too_large", "Payload melebihi batas endpoint.")
	}
	return fail(422, code, message)
}

func NewHandler(store *Store, credentials []Credential, webOrigin string) (http.Handler, error) {
	if store == nil || len(credentials) == 0 {
		return nil, errors.New("explicit store and credentials required")
	}
	seen := make(map[string]bool)
	for _, c := range credentials {
		if len(c.Token) < 24 || c.TenantID == "" || (c.Kind != "user" && c.Kind != "device") {
			return nil, errors.New("explicit credentials of at least 24 characters required")
		}
		if seen[c.Token] {
			return nil, errors.New("user and device tokens must be distinct")
		}
		seen[c.Token] = true
	}
	origins := map[string]bool{"http://localhost:7357": true, "http://127.0.0.1:7357": true}
	if webOrigin != "" {
		if !localOrigin.MatchString(webOrigin) {
			return nil, errors.New("demo web origin must be an exact loopback HTTP origin")
		}
		origins[webOrigin] = true
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestID := newID()
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Request-Id", requestID)
		w.Header().Set("Vary", "Origin")
		respond := func(status int, body any) {
			w.WriteHeader(status)
			if body != nil {
				_ = json.NewEncoder(w).Encode(body)
			}
		}
		reject := func(problem *APIError) {
			respond(problem.Status, map[string]any{"error": map[string]string{"code": problem.Code, "message": problem.Message, "requestId": requestID}})
		}
		if origin := r.Header.Get("Origin"); origin != "" {
			if !origins[origin] {
				reject(fail(403, "origin_denied", "Origin tidak diizinkan."))
				return
			}
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		}
		if r.Method == http.MethodOptions {
			respond(204, nil)
			return
		}
		if r.Method == http.MethodGet && r.URL.Path == "/health" {
			persistence := "memory"
			if store.dataFile != "" {
				persistence = "json_snapshot"
			}
			respond(200, map[string]any{"status": "ok", "mode": "demo", "persistence": persistence, "hardwareCommands": false})
			return
		}
		authorization := r.Header.Get("Authorization")
		if !strings.HasPrefix(authorization, "Bearer ") || len(authorization) > 1024 {
			reject(fail(401, "unauthorized", "Bearer token diperlukan."))
			return
		}
		provided := sha256.Sum256([]byte(strings.TrimPrefix(authorization, "Bearer ")))
		var principal *Credential
		for _, candidate := range credentials {
			expected := sha256.Sum256([]byte(candidate.Token))
			if subtle.ConstantTimeCompare(provided[:], expected[:]) == 1 {
				principal = &candidate
			}
		}
		if principal == nil {
			reject(fail(401, "unauthorized", "Token tidak valid."))
			return
		}
		if r.Method == http.MethodPost && r.URL.Path == "/v1/telemetry" {
			if principal.Kind != "device" {
				reject(fail(403, "device_only", "Ingest memerlukan kredensial perangkat."))
				return
			}
			contentType := strings.ToLower(strings.TrimSpace(strings.Split(r.Header.Get("Content-Type"), ";")[0]))
			if contentType != "application/json" {
				reject(fail(415, "unsupported_media_type", "Gunakan application/json."))
				return
			}
			var input TelemetryInput
			if problem := decodeBody(w, r, &input, 16384, "invalid_telemetry", "JSON atau field tidak valid. Identitas unit ditentukan server."); problem != nil {
				reject(problem)
				return
			}
			result, problem := store.Ingest(*principal, input)
			if problem != nil {
				reject(problem)
				return
			}
			respond(202, result)
			return
		}
		if principal.Kind != "user" {
			reject(fail(403, "user_only", "Perangkat tidak boleh membaca armada."))
			return
		}
		if r.Method == http.MethodPost {
			if r.URL.Path == "/v1/bookings" || r.URL.Path == "/v1/work-orders" {
				if strings.ToLower(strings.TrimSpace(strings.Split(r.Header.Get("Content-Type"), ";")[0])) != "application/json" {
					reject(fail(415, "unsupported_media_type", "Gunakan application/json."))
					return
				}
				if r.URL.Path == "/v1/bookings" {
					var input BookingInput
					if problem := decodeBody(w, r, &input, 4096, "invalid_booking", "Payload booking tidak valid."); problem != nil {
						reject(problem)
						return
					}
					booking, problem := store.CreateBooking(principal.TenantID, input)
					if problem != nil {
						reject(problem)
						return
					}
					respond(201, map[string]any{"mode": "demo", "booking": booking})
					return
				}
				var input WorkOrderInput
				if problem := decodeBody(w, r, &input, 4096, "invalid_work_order", "Payload work order tidak valid."); problem != nil {
					reject(problem)
					return
				}
				order, problem := store.CreateWorkOrder(principal.TenantID, input)
				if problem != nil {
					reject(problem)
					return
				}
				respond(201, map[string]any{"mode": "demo", "workOrder": order})
				return
			}
			if match := bookingReturnRoute.FindStringSubmatch(r.URL.Path); match != nil {
				booking, problem := store.ReturnBooking(principal.TenantID, match[1])
				if problem != nil {
					reject(problem)
					return
				}
				respond(200, map[string]any{"mode": "demo", "booking": booking})
				return
			}
			if match := workOrderCompleteRoute.FindStringSubmatch(r.URL.Path); match != nil {
				order, problem := store.CompleteWorkOrder(principal.TenantID, match[1])
				if problem != nil {
					reject(problem)
					return
				}
				respond(200, map[string]any{"mode": "demo", "workOrder": order})
				return
			}
			if match := ackRoute.FindStringSubmatch(r.URL.Path); match != nil {
				alert, problem := store.Acknowledge(principal.TenantID, match[1])
				if problem != nil {
					reject(problem)
					return
				}
				respond(200, map[string]any{"mode": "demo", "alert": alert})
				return
			}
			if match := assignmentRoute.FindStringSubmatch(r.URL.Path); match != nil {
				if strings.ToLower(strings.TrimSpace(strings.Split(r.Header.Get("Content-Type"), ";")[0])) != "application/json" {
					reject(fail(415, "unsupported_media_type", "Gunakan application/json."))
					return
				}
				var input struct {
					DriverID string `json:"driverId"`
				}
				if problem := decodeBody(w, r, &input, 1024, "invalid_assignment", "Isi driverId yang valid."); problem != nil {
					reject(problem)
					return
				}
				if input.DriverID == "" {
					reject(fail(422, "invalid_assignment", "Isi driverId yang valid."))
					return
				}
				vehicle, assignment, problem := store.Assign(principal.TenantID, match[1], input.DriverID)
				if problem != nil {
					reject(problem)
					return
				}
				respond(200, map[string]any{"mode": "demo", "vehicle": vehicle, "assignment": assignment})
				return
			}
		}
		if r.Method == http.MethodGet {
			switch r.URL.Path {
			case "/v1/reports/summary":
				respond(200, store.Report(principal.TenantID))
				return
			case "/v1/reports/telemetry.csv":
				w.Header().Set("Content-Type", "text/csv; charset=utf-8")
				w.Header().Set("Content-Disposition", `attachment; filename="revtrack-telemetry-demo.csv"`)
				_ = store.ExportTelemetry(principal.TenantID, w)
				return
			case "/v1/bookings":
				respond(200, map[string]any{"mode": "demo", "bookings": store.Bookings(principal.TenantID)})
				return
			case "/v1/work-orders":
				respond(200, map[string]any{"mode": "demo", "workOrders": store.WorkOrders(principal.TenantID)})
				return
			case "/v1/drivers":
				respond(200, map[string]any{"mode": "demo", "drivers": store.Drivers(principal.TenantID)})
				return
			case "/v1/audit":
				respond(200, map[string]any{"mode": "demo", "events": store.Audit(principal.TenantID)})
				return
			case "/v1/fleet":
				respond(200, store.Fleet(principal.TenantID))
				return
			case "/v1/alerts":
				respond(200, map[string]any{"mode": "demo", "alerts": store.Alerts(principal.TenantID)})
				return
			}
			if match := vehicleRoute.FindStringSubmatch(r.URL.Path); match != nil {
				if match[2] != "" {
					points, problem := store.Telemetry(principal.TenantID, match[1])
					if problem != nil {
						reject(problem)
						return
					}
					respond(200, map[string]any{"mode": "demo", "vehicleId": match[1], "limit": MaxPoints, "points": points})
					return
				}
				vehicle, problem := store.Vehicle(principal.TenantID, match[1])
				if problem != nil {
					reject(problem)
					return
				}
				respond(200, map[string]any{"mode": "demo", "vehicle": vehicle})
				return
			}
		}
		reject(fail(404, "not_found", "Endpoint tidak ditemukan."))
	}), nil
}
