// Package shortener は短縮コードの発行・解決・クリック集計を行う。
// 永続化は Store インターフェースの裏に隠し、まずはメモリ実装で提供する(Phase 7 以降で DB 実装に差し替え可能)。
package shortener

import (
	"crypto/rand"
	"errors"
	"math/big"
	"sync"
)

// ErrNotFound は存在しないコードを解決しようとした時に返る。
var ErrNotFound = errors.New("shortener: code not found")

// Link は短縮コードと元 URL、クリック数の組。
type Link struct {
	Code   string
	Target string
	Clicks int64
}

// Store は短縮リンクの保存先。実装は並行アクセスに対して安全でなければならない。
type Store interface {
	// Create は target に対する新しいコードを発行する。同じ target が既にあれば既存を返し created=false。
	Create(target string) (link Link, created bool, err error)
	// Resolve はコードから target を返し、クリック数を 1 増やす。
	Resolve(code string) (string, error)
	// Stats は現在のクリック数を返す(増やさない)。
	Stats(code string) (Link, error)
}

const (
	codeAlphabet = "abcdefghijkmnpqrstuvwxyz23456789" // 見間違えやすい l/o/0/1 を除いた 32 文字
	codeLength   = 7
)

// MemoryStore は sync.Mutex で保護したメモリ実装。テストと開発用。
type MemoryStore struct {
	mu       sync.Mutex
	byCode   map[string]*Link
	byTarget map[string]string
	newCode  func() (string, error)
}

// NewMemoryStore は空の MemoryStore を返す。
func NewMemoryStore() *MemoryStore {
	return &MemoryStore{
		byCode:   make(map[string]*Link),
		byTarget: make(map[string]string),
		newCode:  randomCode,
	}
}

func randomCode() (string, error) {
	b := make([]byte, codeLength)
	max := big.NewInt(int64(len(codeAlphabet)))
	for i := range b {
		n, err := rand.Int(rand.Reader, max)
		if err != nil {
			return "", err
		}
		b[i] = codeAlphabet[n.Int64()]
	}
	return string(b), nil
}

// Create implements Store.
func (s *MemoryStore) Create(target string) (Link, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if code, ok := s.byTarget[target]; ok {
		return *s.byCode[code], false, nil
	}
	for range 5 { // 衝突は 32^7 分の 1。念のため数回まで再試行する
		code, err := s.newCode()
		if err != nil {
			return Link{}, false, err
		}
		if _, taken := s.byCode[code]; taken {
			continue
		}
		l := &Link{Code: code, Target: target}
		s.byCode[code] = l
		s.byTarget[target] = code
		return *l, true, nil
	}
	return Link{}, false, errors.New("shortener: could not allocate a unique code")
}

// Resolve implements Store.
func (s *MemoryStore) Resolve(code string) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	l, ok := s.byCode[code]
	if !ok {
		return "", ErrNotFound
	}
	l.Clicks++
	return l.Target, nil
}

// Stats implements Store.
func (s *MemoryStore) Stats(code string) (Link, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	l, ok := s.byCode[code]
	if !ok {
		return Link{}, ErrNotFound
	}
	return *l, nil
}
