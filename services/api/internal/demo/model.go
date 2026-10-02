// Package demo is a local, fictional fleet prototype. No hardware command is implemented.
package demo

import (
	"crypto/rand"
	"encoding/hex"
	"time"
)

type APIError struct {
	Status  int    `json:"-"`
	Code    string `json:"code"`
	Message string `json:"message"`
}

func (e *APIError) Error() string                     { return e.Message }
func fail(status int, code, message string) *APIError { return &APIError{status, code, message} }

type Credential struct{ Token, Kind, TenantID, DeviceID string }
type Driver struct {
	ID     string  `json:"id"`
	Name   string  `json:"name"`
	Rating float64 `json:"rating"`
}
type Location struct {
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
	Label     string  `json:"label"`
}
type Vehicle struct {
	ID             string   `json:"id"`
	Plate          string   `json:"plate"`
	Name           string   `json:"name"`
	Powertrain     string   `json:"powertrain"`
	Status         string   `json:"status"`
	Driver         Driver   `json:"driver"`
	Location       Location `json:"location"`
	SpeedKph       float64  `json:"speedKph"`
	BatteryPercent *float64 `json:"batteryPercent"`
	FuelPercent    *float64 `json:"fuelPercent"`
	OdometerKm     float64  `json:"odometerKm"`
	RangeKm        *float64 `json:"rangeKm"`
	LastSeenAt     string   `json:"lastSeenAt"`
	LastPositionAt string   `json:"lastPositionAt"`
	EnergyAt       *string  `json:"energyAt"`
	Signal         string   `json:"signal"`
	TripTodayKm    float64  `json:"tripTodayKm"`
	Source         string   `json:"source"`
	Ignition       bool     `json:"ignition"`
}

type Summary struct {
	Total   int `json:"total"`
	Moving  int `json:"moving"`
	Idle    int `json:"idle"`
	Offline int `json:"offline"`
	Alerts  int `json:"alerts"`
}
type Fleet struct {
	Mode        string    `json:"mode"`
	GeneratedAt string    `json:"generatedAt"`
	Vehicles    []Vehicle `json:"vehicles"`
	Summary     Summary   `json:"summary"`
}
type Alert struct {
	ID              string `json:"id"`
	VehicleID       string `json:"vehicleId"`
	Title           string `json:"title"`
	Description     string `json:"description"`
	Severity        string `json:"severity"`
	Type            string `json:"type"`
	CreatedAt       string `json:"createdAt"`
	Status          string `json:"status"`
	Source          string `json:"source"`
	EvidenceEventID string `json:"evidenceEventId,omitempty"`
}

type TelemetryInput struct {
	EventID        string   `json:"eventId"`
	Sequence       int64    `json:"sequence"`
	RecordedAt     string   `json:"recordedAt"`
	Latitude       *float64 `json:"latitude"`
	Longitude      *float64 `json:"longitude"`
	SpeedKph       *float64 `json:"speedKph"`
	Ignition       *bool    `json:"ignition"`
	AccuracyM      *float64 `json:"accuracyM"`
	BatteryPercent *float64 `json:"batteryPercent,omitempty"`
	FuelPercent    *float64 `json:"fuelPercent,omitempty"`
	OdometerKm     *float64 `json:"odometerKm,omitempty"`
}
type Point struct {
	EventID        string   `json:"eventId,omitempty"`
	Sequence       int64    `json:"sequence,omitempty"`
	RecordedAt     string   `json:"recordedAt"`
	ReceivedAt     string   `json:"receivedAt,omitempty"`
	Latitude       float64  `json:"latitude"`
	Longitude      float64  `json:"longitude"`
	SpeedKph       float64  `json:"speedKph"`
	AccuracyM      float64  `json:"accuracyM"`
	BatteryPercent *float64 `json:"batteryPercent"`
	FuelPercent    *float64 `json:"fuelPercent"`
	OdometerKm     *float64 `json:"odometerKm"`
	Source         string   `json:"source"`
}
type Accepted struct {
	Mode      string  `json:"mode"`
	Accepted  bool    `json:"accepted"`
	VehicleID string  `json:"vehicleId"`
	EventID   string  `json:"eventId"`
	Alerts    []Alert `json:"alerts"`
}

type Assignment struct {
	ID         string `json:"id"`
	VehicleID  string `json:"vehicleId"`
	DriverID   string `json:"driverId"`
	AssignedAt string `json:"assignedAt"`
}
type AuditEvent struct {
	ID         string `json:"id"`
	Action     string `json:"action"`
	VehicleID  string `json:"vehicleId,omitempty"`
	AlertID    string `json:"alertId,omitempty"`
	DriverID   string `json:"driverId,omitempty"`
	ResourceID string `json:"resourceId,omitempty"`
	Actor      string `json:"actor"`
	CreatedAt  string `json:"createdAt"`
}

type Booking struct {
	ID           string `json:"id"`
	VehicleID    string `json:"vehicleId"`
	CustomerName string `json:"customerName"`
	StartAt      string `json:"startAt"`
	EndAt        string `json:"endAt"`
	Status       string `json:"status"`
	CreatedAt    string `json:"createdAt"`
	ReturnedAt   string `json:"returnedAt,omitempty"`
}
type BookingInput struct {
	VehicleID    string `json:"vehicleId"`
	CustomerName string `json:"customerName"`
	StartAt      string `json:"startAt"`
	EndAt        string `json:"endAt"`
}
type WorkOrder struct {
	ID          string `json:"id"`
	VehicleID   string `json:"vehicleId"`
	Title       string `json:"title"`
	Status      string `json:"status"`
	CreatedAt   string `json:"createdAt"`
	CompletedAt string `json:"completedAt,omitempty"`
}
type WorkOrderInput struct {
	VehicleID string `json:"vehicleId"`
	Title     string `json:"title"`
}

const isoLayout = "2006-01-02T15:04:05.000Z"

func iso(t time.Time) string    { return t.UTC().Format(isoLayout) }
func pointer[T any](value T) *T { return &value }
func newID() string {
	var data [16]byte
	if _, err := rand.Read(data[:]); err != nil {
		panic(err)
	}
	return hex.EncodeToString(data[:])
}

// Ring keeps the newest capacity records. Append is O(1); Values is O(n),
// ordered oldest-to-newest. The Store mutex owns synchronization.
type Ring[T any] struct {
	data        []T
	next, count int
}

func NewRing[T any](capacity int) *Ring[T] { return &Ring[T]{data: make([]T, capacity)} }
func (r *Ring[T]) Append(value T) (evicted T, hadEviction bool) {
	hadEviction = r.count == len(r.data)
	if hadEviction {
		evicted = r.data[r.next]
	} else {
		r.count++
	}
	r.data[r.next] = value
	r.next = (r.next + 1) % len(r.data)
	return
}
func (r *Ring[T]) Values() []T {
	result := make([]T, r.count)
	start := (r.next - r.count + len(r.data)) % len(r.data)
	for i := range result {
		result[i] = r.data[(start+i)%len(r.data)]
	}
	return result
}
