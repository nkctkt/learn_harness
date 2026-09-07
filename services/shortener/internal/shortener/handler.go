package shortener

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"net/url"
	"regexp"
)

var codePattern = regexp.MustCompile(`^[a-z2-9]{7}$`)

// Handler は HTTP API を組み立てる。
//
//	GET  /health         → {"status":"ok","service":"shortener"}
//	POST /links {target} → 201 {"code","target"}(既存なら 200)
//	GET  /{code}         → 302 Location: target(クリック +1)
//	GET  /stats/{code}   → {"code","target","clicks"}
func Handler(store Store, log *slog.Logger) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok", "service": "shortener"})
	})
	mux.HandleFunc("POST /links", func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Target string `json:"target"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&body); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid json"})
			return
		}
		if err := validateTarget(body.Target); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		link, created, err := store.Create(body.Target)
		if err != nil {
			log.Error("create failed", "err", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
			return
		}
		status := http.StatusOK
		if created {
			status = http.StatusCreated
		}
		writeJSON(w, status, map[string]string{"code": link.Code, "target": link.Target})
	})
	mux.HandleFunc("GET /stats/{code}", func(w http.ResponseWriter, r *http.Request) {
		code := r.PathValue("code")
		l, err := store.Stats(code)
		if errors.Is(err, ErrNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "not found"})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"code": l.Code, "target": l.Target, "clicks": l.Clicks})
	})
	mux.HandleFunc("GET /{code}", func(w http.ResponseWriter, r *http.Request) {
		code := r.PathValue("code")
		if !codePattern.MatchString(code) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "not found"})
			return
		}
		target, err := store.Resolve(code)
		if errors.Is(err, ErrNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "not found"})
			return
		}
		// 短縮 URL サービスなので「保存済みの外部 URL へ転送する」こと自体が目的。
		// 作成時に validateTarget 済みだが、保存先が差し替えられた場合に備えてここでも再検証する。
		if err := validateTarget(target); err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "stored target is invalid"})
			return
		}
		http.Redirect(w, r, target, http.StatusFound) //nolint:gosec // G710: 再検証済みの保存値へのリダイレクトはこのサービスの仕様
	})
	return mux
}

func validateTarget(raw string) error {
	if raw == "" {
		return errors.New("target is required")
	}
	if len(raw) > 2048 {
		return errors.New("target is too long")
	}
	u, err := url.Parse(raw)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return errors.New("target must be an absolute http(s) url")
	}
	return nil
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
