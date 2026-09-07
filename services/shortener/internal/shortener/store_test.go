package shortener

import (
	"errors"
	"sync"
	"testing"
)

func TestCreateIsIdempotentPerTarget(t *testing.T) {
	s := NewMemoryStore()
	a, created, err := s.Create("https://example.com/a")
	if err != nil || !created {
		t.Fatalf("first create: created=%v err=%v", created, err)
	}
	b, created, err := s.Create("https://example.com/a")
	if err != nil || created {
		t.Fatalf("second create: created=%v err=%v", created, err)
	}
	if a.Code != b.Code {
		t.Fatalf("expected same code, got %q and %q", a.Code, b.Code)
	}
	if len(a.Code) != codeLength {
		t.Fatalf("code length %d, want %d", len(a.Code), codeLength)
	}
}

func TestResolveCountsClicksAndStatsDoesNot(t *testing.T) {
	s := NewMemoryStore()
	l, _, _ := s.Create("https://example.com/x")
	for range 3 {
		if _, err := s.Resolve(l.Code); err != nil {
			t.Fatal(err)
		}
	}
	got, err := s.Stats(l.Code)
	if err != nil || got.Clicks != 3 {
		t.Fatalf("clicks=%d err=%v, want 3", got.Clicks, err)
	}
	if _, err := s.Stats(l.Code); err != nil {
		t.Fatal(err)
	}
	got, _ = s.Stats(l.Code)
	if got.Clicks != 3 {
		t.Fatalf("Stats must not increment: clicks=%d", got.Clicks)
	}
}

func TestUnknownCode(t *testing.T) {
	s := NewMemoryStore()
	if _, err := s.Resolve("zzzzzzz"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("want ErrNotFound, got %v", err)
	}
	if _, err := s.Stats("zzzzzzz"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("want ErrNotFound, got %v", err)
	}
}

// -race で意味を持つテスト: 並行にクリックしても数が合うこと。
func TestConcurrentResolveIsRaceFree(t *testing.T) {
	s := NewMemoryStore()
	l, _, _ := s.Create("https://example.com/hot")
	const workers, each = 16, 250
	var wg sync.WaitGroup
	for range workers {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for range each {
				if _, err := s.Resolve(l.Code); err != nil {
					t.Error(err)
					return
				}
			}
		}()
	}
	wg.Wait()
	got, _ := s.Stats(l.Code)
	if got.Clicks != workers*each {
		t.Fatalf("clicks=%d, want %d", got.Clicks, workers*each)
	}
}

func TestCodeCollisionRetries(t *testing.T) {
	s := NewMemoryStore()
	codes := []string{"aaaaaaa", "aaaaaaa", "bbbbbbb"}
	i := 0
	s.newCode = func() (string, error) { c := codes[i]; i++; return c, nil }
	first, _, _ := s.Create("https://example.com/1")
	second, _, _ := s.Create("https://example.com/2")
	if first.Code != "aaaaaaa" || second.Code != "bbbbbbb" {
		t.Fatalf("got %q %q", first.Code, second.Code)
	}
}
