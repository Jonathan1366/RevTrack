// Simulator generates fictional measurements for dev-001. It never contacts a car.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"math"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"strings"
	"time"
)

func main() {
	count := flag.Int("count", 0, "number of fictional points; 0 continues until Ctrl-C")
	interval := flag.Duration("interval", 3*time.Second, "interval, minimum 1s")
	flag.Parse()
	if *interval < time.Second || *count < 0 {
		log.Fatal("interval >=1s and count >=0 required")
	}
	base := os.Getenv("REVTRACK_API_URL")
	if base == "" {
		base = "http://127.0.0.1:8080"
	}
	parsed, err := url.Parse(base)
	if err != nil || parsed.Scheme != "http" || (parsed.Hostname() != "127.0.0.1" && parsed.Hostname() != "localhost") || parsed.User != nil {
		log.Fatal("REVTRACK_API_URL must be a loopback HTTP URL")
	}
	token := os.Getenv("REVTRACK_DEVICE_TOKEN")
	if len(token) < 24 {
		log.Fatal("REVTRACK_DEVICE_TOKEN required")
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	client := &http.Client{Timeout: 5 * time.Second, CheckRedirect: func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse }}
	for i := 0; *count == 0 || i < *count; i++ {
		now := time.Now().UTC()
		payload := map[string]any{"eventId": fmt.Sprintf("sim-%d", now.UnixNano()), "sequence": now.UnixMilli(), "recordedAt": now.Format("2006-01-02T15:04:05.000Z"), "latitude": -6.2088 + math.Sin(float64(i)/12)*0.007, "longitude": 106.8229 + math.Cos(float64(i)/12)*0.009, "speedKph": 35 + i%12*5, "ignition": true, "accuracyM": 8, "batteryPercent": 78 - float64(i%100)/10}
		body, _ := json.Marshal(payload)
		request, err := http.NewRequestWithContext(ctx, http.MethodPost, strings.TrimRight(base, "/")+"/v1/telemetry", bytes.NewReader(body))
		if err != nil {
			log.Fatal(err)
		}
		request.Header.Set("Content-Type", "application/json")
		request.Header.Set("Authorization", "Bearer "+token)
		response, err := client.Do(request)
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			log.Printf("simulator request failed: %v", err)
		} else {
			_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 8192))
			response.Body.Close()
			log.Printf("SIMULATION point=%d status=%d", i+1, response.StatusCode)
		}
		if *count > 0 && i+1 == *count {
			return
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(*interval):
		}
	}
}
