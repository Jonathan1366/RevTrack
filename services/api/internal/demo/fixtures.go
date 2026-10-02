package demo

import "time"

// Every identity, rating, alert and measurement below is fictional.
func (s *Store) seed() {
	now := s.clock()
	vehicles := []Vehicle{
		{ID: "veh-001", Plate: "B 1388 REV", Name: "BYD Seal Premium", Powertrain: "ev", Status: "moving", Driver: Driver{"drv-001", "Arif Pratama", 4.9}, Location: Location{-6.2088, 106.8229, "Sudirman, Jakarta"}, SpeedKph: 42, BatteryPercent: pointer(78.0), OdometerKm: 18420, RangeKm: pointer(386.0), TripTodayKm: 112.4, Ignition: true},
		{ID: "veh-002", Plate: "B 2041 REV", Name: "Hyundai IONIQ 5", Powertrain: "ev", Status: "charging", Driver: Driver{"drv-002", "Dina Putri", 4.9}, Location: Location{-6.2244, 106.8094, "Senayan, Jakarta"}, BatteryPercent: pointer(46.0), OdometerKm: 32650, RangeKm: pointer(185.0), TripTodayKm: 78.8},
		{ID: "veh-003", Plate: "B 1732 REV", Name: "Toyota Avanza Veloz", Powertrain: "ice", Status: "idle", Driver: Driver{"drv-003", "Budi Santoso", 4.7}, Location: Location{-6.1751, 106.8650, "Cempaka Putih, Jakarta"}, FuelPercent: pointer(62.0), OdometerKm: 67512, RangeKm: pointer(342.0), TripTodayKm: 156.2, Ignition: true},
		{ID: "veh-004", Plate: "B 1890 REV", Name: "Mitsubishi Xpander", Powertrain: "ice", Status: "offline", Driver: Driver{"drv-004", "Rizky Ramadhan", 4.8}, Location: Location{-6.2607, 106.7816, "Kebayoran Lama, Jakarta"}, FuelPercent: pointer(31.0), OdometerKm: 44880, RangeKm: pointer(170.0), TripTodayKm: 94.6},
		{ID: "veh-005", Plate: "HE 007 REV", Name: "Komatsu PC200", Powertrain: "diesel", Status: "parked", Driver: Driver{"drv-005", "Agus Setiawan", 4.8}, Location: Location{-6.1352, 106.8133, "Penjaringan, Jakarta"}, FuelPercent: pointer(84.0), OdometerKm: 1200, TripTodayKm: 2.1},
	}
	age := []time.Duration{8, 15, 30, 1140, 40}
	primary := &tenantData{vehicles: make(map[string]Vehicle), points: make(map[string]*Ring[Point]), alerts: NewRing[Alert](MaxAlerts)}
	s.tenants["tenant-demo"] = primary
	for index, v := range vehicles {
		v.LastSeenAt = iso(now.Add(-age[index] * time.Second))
		v.LastPositionAt = v.LastSeenAt
		v.EnergyAt = pointer(v.LastSeenAt)
		v.Signal = "good"
		if v.Status == "offline" {
			v.Signal = "offline"
		}
		v.Source = "fixture"
		primary.vehicles[v.ID] = v
		primary.points[v.ID] = NewRing[Point](MaxPoints)
		for i := range 18 {
			lat, lng := v.Location.Latitude, v.Location.Longitude
			speed := 0.0
			if v.Status == "moving" {
				lat -= float64(17-i) * 0.0006
				lng -= float64(17-i) * 0.00035
				speed = 28 + float64(i%7)*4
			}
			battery, fuel := v.BatteryPercent, v.FuelPercent
			if battery != nil {
				battery = pointer(*battery + float64(17-i)*0.25)
			}
			if fuel != nil {
				fuel = pointer(*fuel + float64(17-i)*0.1)
			}
			primary.points[v.ID].Append(Point{RecordedAt: iso(now.Add(-age[index]*time.Second - time.Duration(17-i)*time.Minute)), Latitude: lat, Longitude: lng, SpeedKph: speed, AccuracyM: 8, BatteryPercent: battery, FuelPercent: fuel, OdometerKm: pointer(v.OdometerKm - float64(17-i)*0.5), Source: "fixture"})
		}
	}
	otherVehicle := primary.vehicles["veh-001"]
	otherVehicle.ID = "veh-other"
	otherVehicle.Plate = "OTHER TENANT"
	otherPoints := NewRing[Point](MaxPoints)
	for _, p := range primary.points["veh-001"].Values() {
		otherPoints.Append(p)
	}
	s.tenants["tenant-other"] = &tenantData{vehicles: map[string]Vehicle{"veh-other": otherVehicle}, points: map[string]*Ring[Point]{"veh-other": otherPoints}, alerts: NewRing[Alert](MaxAlerts)}
	for _, tenant := range s.tenants {
		tenant.drivers = make(map[string]Driver)
		tenant.audit = NewRing[AuditEvent](500)
		tenant.assignments = NewRing[Assignment](500)
		tenant.bookings = make(map[string]Booking)
		tenant.workOrders = make(map[string]WorkOrder)
		for _, vehicle := range tenant.vehicles {
			tenant.drivers[vehicle.Driver.ID] = vehicle.Driver
		}
	}
	primary.drivers["drv-006"] = Driver{ID: "drv-006", Name: "Nadia Rahma", Rating: 4.9}
	for _, alert := range []Alert{
		{ID: "alert-001", VehicleID: "veh-004", Title: "Tracker tidak tersambung", Description: "Tidak ada laporan selama 19 menit. Periksa jaringan dan daya; ini belum membuktikan manipulasi.", Severity: "high", Type: "device_offline", CreatedAt: iso(now.Add(-17 * time.Minute))},
		{ID: "alert-002", VehicleID: "veh-003", Title: "Mesin menyala saat berhenti", Description: "Idle 12 menit pada data simulasi. Tinjau kebutuhan operasional pengemudi.", Severity: "medium", Type: "excessive_idle", CreatedAt: iso(now.Add(-4 * time.Minute))},
		{ID: "alert-003", VehicleID: "veh-001", Title: "Kecepatan perlu ditinjau", Description: "Riwayat simulasi mencatat 87 km/jam pada kebijakan armada 80 km/jam. Verifikasi batas jalan.", Severity: "medium", Type: "overspeed", CreatedAt: iso(now.Add(-time.Hour))},
	} {
		alert.Source = "fixture"
		alert.Status = "open"
		primary.alerts.Append(alert)
	}
}
