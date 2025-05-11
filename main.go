package main

import (
    "fmt"
    "log"
    "net"
    "net/http"
    "os"
    "os/signal"
    "syscall"
)

func main() {
    // Use an environment variable or default to port 8080
    port := getEnv("PORT", "8080")

    // Define HTTP handlers
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        ip, err := GetLocalIP()
        if err != nil {
            http.Error(w, "Unable to determine local IP", http.StatusInternalServerError)
            log.Printf("Error determining local IP: %v", err)
            return
        }
        w.Write([]byte(ip.String()))
    })

    http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
        w.Write([]byte("OK")) // Use "OK" as a standard health response
    })

    // Log server startup
    log.Printf("Starting server on port %s...", port)

    // Setup graceful shutdown
    server := &http.Server{Addr: ":" + port}
    go func() {
        if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            log.Fatalf("Could not listen on port %s: %v", port, err)
        }
    }()

    // Wait for shutdown signal
    gracefulShutdown(server)
}

// GetLocalIP returns the first non-loopback IP address of the machine
func GetLocalIP() (net.IP, error) {
    conn, err := net.Dial("udp", "8.8.8.8:80")
    if err != nil {
        return nil, err
    }
    defer conn.Close()

    localAddress := conn.LocalAddr().(*net.UDPAddr)
    return localAddress.IP, nil
}

// getEnv retrieves environment variables with a fallback default value
func getEnv(key, fallback string) string {
    if value, exists := os.LookupEnv(key); exists {
        return value
    }
    return fallback
}

// gracefulShutdown handles graceful shutdown of the server
func gracefulShutdown(server *http.Server) {
    quit := make(chan os.Signal, 1)
    signal.Notify(quit, os.Interrupt, syscall.SIGTERM)

    <-quit
    log.Println("Shutting down server...")

    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()

    if err := server.Shutdown(ctx); err != nil {
        log.Fatalf("Error during server shutdown: %v", err)
    }
    log.Println("Server gracefully stopped")
}
