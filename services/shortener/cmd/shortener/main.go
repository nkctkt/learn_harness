// Command shortener は短縮 URL サービスを起動する。
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/nkctkt/learn_harness/services/shortener/internal/shortener"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	addr := ":" + envOr("PORT", "8081")

	// distroless image にはシェルも curl も無いので、HEALTHCHECK は自分自身を healthcheck モードで呼ぶ。
	if len(os.Args) > 1 && os.Args[1] == "-healthcheck" {
		os.Exit(healthcheck("http://127.0.0.1" + addr + "/health"))
	}

	srv := &http.Server{
		Addr:              addr,
		Handler:           shortener.Handler(shortener.NewMemoryStore(), log),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go func() {
		log.Info("shortener listening", "addr", addr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Error("server failed", "err", err)
			os.Exit(1)
		}
	}()

	<-ctx.Done()
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Error("shutdown failed", "err", err)
	}
}

// healthcheck は /health に GET し、200 なら 0、それ以外は 1 を返す(Docker HEALTHCHECK の終了コード規約)。
func healthcheck(url string) int {
	client := &http.Client{Timeout: 2 * time.Second}
	res, err := client.Get(url)
	if err != nil {
		return 1
	}
	defer func() { _ = res.Body.Close() }()
	if res.StatusCode != http.StatusOK {
		return 1
	}
	return 0
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
