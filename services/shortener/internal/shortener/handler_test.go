package shortener

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func newServer(t *testing.T) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(Handler(NewMemoryStore(), slog.New(slog.NewTextHandler(io.Discard, nil))))
	t.Cleanup(srv.Close)
	return srv
}

func postLink(t *testing.T, base, body string) (*http.Response, map[string]string) {
	t.Helper()
	res, err := http.Post(base+"/links", "application/json", strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	var out map[string]string
	_ = json.NewDecoder(res.Body).Decode(&out)
	return res, out
}

func TestCreateThenRedirectThenStats(t *testing.T) {
	srv := newServer(t)
	res, out := postLink(t, srv.URL, `{"target":"https://example.com/docs"}`)
	if res.StatusCode != http.StatusCreated {
		t.Fatalf("status %d", res.StatusCode)
	}
	res2, out2 := postLink(t, srv.URL, `{"target":"https://example.com/docs"}`)
	if res2.StatusCode != http.StatusOK || out2["code"] != out["code"] {
		t.Fatalf("dedupe failed: %d %v", res2.StatusCode, out2)
	}

	client := &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	r, err := client.Get(srv.URL + "/" + out["code"])
	if err != nil {
		t.Fatal(err)
	}
	r.Body.Close()
	if r.StatusCode != http.StatusFound || r.Header.Get("Location") != "https://example.com/docs" {
		t.Fatalf("redirect: %d %q", r.StatusCode, r.Header.Get("Location"))
	}

	st, err := http.Get(srv.URL + "/stats/" + out["code"])
	if err != nil {
		t.Fatal(err)
	}
	defer st.Body.Close()
	var stats struct {
		Clicks int64 `json:"clicks"`
	}
	_ = json.NewDecoder(st.Body).Decode(&stats)
	if stats.Clicks != 1 {
		t.Fatalf("clicks=%d, want 1", stats.Clicks)
	}
}

func TestRejectsBadTargets(t *testing.T) {
	srv := newServer(t)
	for _, body := range []string{
		`{"target":""}`,
		`{"target":"javascript:alert(1)"}`,
		`{"target":"/relative"}`,
		`{"target":"ftp://example.com/x"}`,
		`not json`,
		`{"target":"https://` + strings.Repeat("a", 2050) + `.com"}`,
	} {
		res, _ := postLink(t, srv.URL, body)
		if res.StatusCode != http.StatusBadRequest {
			t.Errorf("%.40s: status %d, want 400", body, res.StatusCode)
		}
	}
}

func TestUnknownAndMalformedCodes(t *testing.T) {
	srv := newServer(t)
	for _, p := range []string{"/zzzzzzz", "/UPPER77", "/short", "/stats/zzzzzzz"} {
		res, err := http.Get(srv.URL + p)
		if err != nil {
			t.Fatal(err)
		}
		res.Body.Close()
		if res.StatusCode != http.StatusNotFound {
			t.Errorf("%s: status %d, want 404", p, res.StatusCode)
		}
	}
}
