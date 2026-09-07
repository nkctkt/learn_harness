package shortener

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/santhosh-tekuri/jsonschema/v6"
)

// 契約テスト(producer 側): api(consumer)が期待する応答の形(contracts/*.schema.json、api の zod から生成)で
// 自分の応答を検証する。フィールド名を変えると、api を起動しなくてもここで落ちる(Exercise 09 の穴を塞ぐ)。
func TestCreateResponseMatchesConsumerContract(t *testing.T) {
	schemaPath := filepath.Join("..", "..", "..", "..", "contracts", "shortener.links.response.schema.json")
	raw, err := os.ReadFile(schemaPath)
	if err != nil {
		t.Fatalf("contract file not found (run `pnpm --filter @shelf/api contracts:export`): %v", err)
	}
	var doc any
	if err := json.Unmarshal(raw, &doc); err != nil {
		t.Fatal(err)
	}
	c := jsonschema.NewCompiler()
	if err := c.AddResource("contract.json", doc); err != nil {
		t.Fatal(err)
	}
	schema, err := c.Compile("contract.json")
	if err != nil {
		t.Fatal(err)
	}

	srv := httptest.NewServer(Handler(NewMemoryStore(), slog.New(slog.NewTextHandler(io.Discard, nil))))
	defer srv.Close()
	res, err := http.Post(srv.URL+"/links", "application/json", strings.NewReader(`{"target":"https://example.com/docs"}`))
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	var body any
	if err := json.NewDecoder(res.Body).Decode(&body); err != nil {
		t.Fatal(err)
	}
	if err := schema.Validate(body); err != nil {
		t.Fatalf("response violates the consumer contract:\n%v", err)
	}
}
