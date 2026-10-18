// Command meridian-server runs the Meridian countdown service.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/YuKiBi0/Meridian/server/internal/api"
	"github.com/YuKiBi0/Meridian/server/internal/store"
	"github.com/YuKiBi0/Meridian/server/internal/stream"
	"github.com/YuKiBi0/Meridian/server/internal/timer"
	"github.com/YuKiBi0/Meridian/server/internal/web"
)

var version = "dev"

type config struct {
	addr         string
	basePath     string
	databaseURL  string
	adminToken   string
	cookieSecure bool
	trusted      []*net.IPNet
}

func env(key, def string) string {
	if v, ok := os.LookupEnv(key); ok {
		return v
	}
	return def
}

func loadConfig() (config, error) {
	c := config{
		addr:         env("MERIDIAN_ADDR", ":8080"),
		basePath:     strings.TrimRight(env("MERIDIAN_BASE_PATH", ""), "/"),
		databaseURL:  env("MERIDIAN_DATABASE_URL", ""),
		adminToken:   env("MERIDIAN_ADMIN_TOKEN", ""),
		cookieSecure: env("MERIDIAN_COOKIE_SECURE", "true") != "false",
	}
	if c.basePath != "" && !strings.HasPrefix(c.basePath, "/") {
		return c, errors.New("MERIDIAN_BASE_PATH must start with /")
	}
	if c.databaseURL == "" {
		return c, errors.New("MERIDIAN_DATABASE_URL is required")
	}
	if len(c.adminToken) < 16 {
		return c, errors.New("MERIDIAN_ADMIN_TOKEN is required and must be at least 16 characters")
	}
	for _, cidr := range strings.Split(env("MERIDIAN_TRUSTED_PROXY", "127.0.0.1/32,172.16.0.0/12"), ",") {
		if cidr = strings.TrimSpace(cidr); cidr == "" {
			continue
		}
		_, n, err := net.ParseCIDR(cidr)
		if err != nil {
			return c, fmt.Errorf("MERIDIAN_TRUSTED_PROXY: %w", err)
		}
		c.trusted = append(c.trusted, n)
	}
	return c, nil
}

// listener connects the engine to the SSE hub and the database.
type listener struct {
	hub     *stream.Hub
	persist *store.Persister
}

func (l listener) State(s timer.State)       { l.hub.Publish(stream.Encode("state", s.Seq, s)) }
func (l listener) Reminder(f timer.Fired)    { l.hub.Publish(stream.Encode("reminder", -1, f)) }
func (l listener) Persist(p timer.Persisted) { l.persist.Save(p) }

func main() {
	slog.SetDefault(slog.New(slog.NewTextHandler(os.Stdout, nil)))
	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "healthcheck":
			os.Exit(healthcheck())
		case "version":
			fmt.Println(version)
			return
		}
	}
	if err := run(); err != nil {
		slog.Error("fatal", "err", err)
		os.Exit(1)
	}
}

func run() error {
	cfg, err := loadConfig()
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	var st *store.Store
	for attempt := 1; ; attempt++ {
		openCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
		st, err = store.Open(openCtx, cfg.databaseURL)
		cancel()
		if err == nil {
			break
		}
		if attempt == 10 || ctx.Err() != nil {
			return fmt.Errorf("open database: %w", err)
		}
		slog.Warn("database not ready, retrying", "err", err, "attempt", attempt)
		time.Sleep(2 * time.Second)
	}
	defer st.Close()

	t := timer.New()
	if p, ok, err := st.LoadTimer(ctx); err != nil {
		return fmt.Errorf("load timer: %w", err)
	} else if ok {
		t = timer.Restore(p, time.Now())
		slog.Info("restored timer", "status", t.Status(), "seq", t.Seq())
	}

	hub := stream.NewHub()
	persister := store.NewPersister(st)
	engine := timer.NewEngine(t, listener{hub: hub, persist: persister})

	srv := api.New(api.Config{
		BasePath:     cfg.basePath,
		AdminToken:   cfg.adminToken,
		CookieSecure: cfg.cookieSecure,
		Trusted:      cfg.trusted,
		Console:      web.FS(),
	}, engine, hub, st)

	httpSrv := &http.Server{
		Addr:              cfg.addr,
		Handler:           srv.Handler(),
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       2 * time.Minute,
		// No WriteTimeout: SSE responses stay open indefinitely.
	}
	errc := make(chan error, 1)
	go func() {
		slog.Info("meridian-server listening", "addr", cfg.addr, "base", cfg.basePath, "version", version)
		errc <- httpSrv.ListenAndServe()
	}()

	select {
	case err := <-errc:
		return err
	case <-ctx.Done():
	}
	slog.Info("shutting down")
	shutCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	engine.Close()
	// SSE connections never finish on their own; Close ends them.
	httpSrv.Close()
	persister.Close(shutCtx)
	return nil
}

func healthcheck() int {
	addr := env("MERIDIAN_ADDR", ":8080")
	if strings.HasPrefix(addr, ":") {
		addr = "127.0.0.1" + addr
	}
	base := strings.TrimRight(env("MERIDIAN_BASE_PATH", ""), "/")
	client := http.Client{Timeout: 3 * time.Second}
	resp, err := client.Get("http://" + addr + base + "/healthz")
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		fmt.Fprintln(os.Stderr, "status", resp.StatusCode)
		return 1
	}
	return 0
}
