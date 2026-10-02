package main

import (
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"revtrack.local/api/internal/demo"
)

func main() {
	userToken, deviceToken := os.Getenv("REVTRACK_DEMO_TOKEN"), os.Getenv("REVTRACK_DEVICE_TOKEN")
	for _, token := range []string{userToken, deviceToken} {
		if len(token) < 24 || strings.HasPrefix(token, "replace-") {
			log.Fatal("Set different random REVTRACK_DEMO_TOKEN and REVTRACK_DEVICE_TOKEN (at least 24 characters). See services/api/README.md.")
		}
	}
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	value, err := strconv.Atoi(port)
	if err != nil || value < 1024 || value > 65535 {
		log.Fatal("PORT must be 1024..65535")
	}
	store, err := demo.OpenStore(nil, os.Getenv("REVTRACK_DATA_FILE"))
	if err != nil {
		log.Fatal(err)
	}
	handler, err := demo.NewHandler(store, []demo.Credential{{Token: userToken, Kind: "user", TenantID: "tenant-demo"}, {Token: deviceToken, Kind: "device", TenantID: "tenant-demo", DeviceID: "dev-001"}}, os.Getenv("REVTRACK_WEB_ORIGIN"))
	if err != nil {
		log.Fatal(err)
	}
	server := &http.Server{Addr: "127.0.0.1:" + port, Handler: handler, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 10 * time.Second, IdleTimeout: 30 * time.Second, MaxHeaderBytes: 8192}
	log.Printf("RevTrack DEMO API http://%s; fictional fixtures, optional JSON snapshot, no vehicle commands", server.Addr)
	log.Fatal(server.ListenAndServe())
}
