package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/urfave/cli/v3"
	_ "modernc.org/sqlite"
)

func moralisAPITokenValues() cli.ValueSourceChain {
	chain := cli.EnvVars("MORALIS_API_TOKEN")
	chain.Append(cli.Files("moralis_api_token"))

	return chain
}

var apiCommand = &cli.Command{
	Name:   "api",
	Usage:  "run the API server",
	Action: runAPI,
	Flags: []cli.Flag{
		&cli.StringFlag{
			Name:  "api-addr",
			Usage: "Listening address",
			Value: "0.0.0.0:10000",
		},
		&cli.StringFlag{
			Name:    "moralis-api-token",
			Usage:   "Moralis API Token",
			Sources: moralisAPITokenValues(),
		},
	},
}

var app = &cli.Command{
	Name:        filepath.Base(os.Args[0]),
	Version:     "v0.0.1",
	HideVersion: true,
	Flags:       nil,
	Commands: []*cli.Command{
		apiCommand,
	},
}

type AssetCategory string

const (
	AssetCategoryERC20   AssetCategory = "ERC20"
	AssetCategoryERC721  AssetCategory = "ERC721"
	AssetCategoryERC1155 AssetCategory = "ERC1155"
)

type Asset struct {
	Name     string        `json:"name"`
	Ticker   string        `json:"ticker"`
	LogoURL  string        `json:"logo_url"`
	Price    string        `json:"price"`
	Category AssetCategory `json:"category"`
	Address  string        `json:"address"`
	ID       uint64        `json:"id,string"`
	Amount   uint64        `json:"amount,string"`
	Deciamls int64         `json:"decimals"`
}

type Token struct {
	TokenAddress     string  `json:"token_address"`
	Symbol           string  `json:"symbol"`
	Name             string  `json:"name"`
	Logo             *string `json:"logo"`
	Thumbnail        *string `json:"thumbnail"`
	Decimals         uint64  `json:"decimals"`
	Balance          string  `json:"balance"`
	PossibleSpam     bool    `json:"possible_spam"`
	VerifiedContract bool    `json:"verified_contract"`
}

type NFT struct {
	TokenID               string    `json:"token_id"`
	TokenAddress          string    `json:"token_address"`
	ContractType          string    `json:"contract_type"`
	LastMetadataSync      time.Time `json:"last_metadata_sync"`
	LastTokenURISync      time.Time `json:"last_token_uri_sync"`
	Name                  string    `json:"name"`
	Symbol                string    `json:"symbol"`
	TokenHash             string    `json:"token_hash"`
	TokenURI              string    `json:"token_uri"`
	VerifiedCollection    bool      `json:"verified_collection"`
	PossibleSpam          bool      `json:"possible_spam"`
	CollectionLogo        string    `json:"collection_logo"`
	CollectionBannerImage string    `json:"collection_banner_image"`
}

type Assets struct {
	Tokens []Token `json:"tokens"`
	NFTs   []NFT   `json:"nfts"`
}

type NFTResponse struct {
	Status   string `json:"status"`
	Page     uint64 `json:"page"`
	PageSize uint64 `json:"page_size"`
	Cursor   string `json:"cursor"`
	Result   []NFT  `json:"result"`
}

type Server struct {
	moralisAPIToken string
	db              *sql.DB
}

func (s *Server) fetchTokens(chain string, address string) ([]Token, error) {
	url := fmt.Sprintf("https://deep-index.moralis.io/api/v2.2/%s/erc20?chain=%s&exclude_spam=false", address, chain)
	slog.Log(context.Background(), slog.LevelInfo, "fetch tokens", "url", url)

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("new request: %w", err)
	}

	req.Header.Add("Accept", "application/json")
	req.Header.Add("X-API-Key", s.moralisAPIToken)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("http request: %w", err)
	}
	defer resp.Body.Close()

	decoder := json.NewDecoder(resp.Body)

	var tokens []Token
	err = decoder.Decode(&tokens)
	if err != nil {
		return nil, fmt.Errorf("decode response: %w", err)
	}

	return tokens, nil
}

func (s *Server) fetchNFTs(chain string, address string) ([]NFT, error) {
	url := fmt.Sprintf("https://deep-index.moralis.io/api/v2.2/%s/nft?format=decimal&chain=%s&exclude_spam=false", address, chain)
	slog.Log(context.Background(), slog.LevelInfo, "fetch nfts", "url", url)

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("new request: %w", err)
	}

	req.Header.Add("Accept", "application/json")
	req.Header.Add("X-API-Key", s.moralisAPIToken)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("http request: %w", err)
	}
	defer resp.Body.Close()

	decoder := json.NewDecoder(resp.Body)

	var response NFTResponse
	err = decoder.Decode(&response)
	if err != nil {
		return nil, fmt.Errorf("decode response: %w", err)
	}

	return response.Result, nil
}

func validateChain(w http.ResponseWriter, chain string) bool {
	switch chain {
	case "eth", "sepolia":
		return true
	default:
		w.WriteHeader(http.StatusBadRequest)
		fmt.Fprintf(w, "%s is not a valid chain name\n", chain)

		return false
	}
}

func isHexCharacter(c byte) bool {
	return ('0' <= c && c <= '9') || ('a' <= c && c <= 'f') || ('A' <= c && c <= 'F')
}

func isHex(str string) bool {
	if len(str)%2 != 0 {
		return false
	}

	for _, c := range []byte(str) {
		if !isHexCharacter(c) {
			return false
		}
	}

	return true
}

func validateAddress(w http.ResponseWriter, address string) bool {
	if strings.HasPrefix(address, "0x") && isHex(address[2:]) {
		return true
	}

	w.WriteHeader(http.StatusBadRequest)
	fmt.Fprintf(w, "%s is not a valid address\n", address)

	return false
}

func (s *Server) dbFetchAssets(ctx context.Context, chain string, address string) (*Assets, error) {
	row := s.db.QueryRowContext(ctx, `
		SELECT assets FROM assets WHERE chain = $1 AND address = $2
	`, chain, address)

	var assetsJSON []byte
	err := row.Scan(assetsJSON)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return &Assets{}, nil
		}

		return nil, fmt.Errorf("scan: %w", err)
	}

	var assets Assets
	err = json.Unmarshal(assetsJSON, &assets)
	if err != nil {
		return nil, fmt.Errorf("unmarshal assets: %w", err)
	}

	return &assets, nil
}

func (s *Server) assetsHandler(w http.ResponseWriter, r *http.Request) {
	setCORS(w)
	ctx := r.Context()

	chain := r.PathValue("chain")
	address := r.PathValue("address")
	slog.Log(
		ctx,
		slog.LevelInfo,
		"asset handler",
		"chain", chain,
		"address", address,
	)

	if ok := validateChain(w, chain); !ok {
		return
	}

	if ok := validateAddress(w, address); !ok {
		return
	}

	assets, err := s.dbFetchAssets(ctx, chain, address)
	if err != nil {
		slog.Log(ctx, slog.LevelError, "db fetch assets failed", "err", err)

		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintln(w, "Internal Server Error")

		return
	}

	w.WriteHeader(http.StatusOK)

	encoder := json.NewEncoder(w)
	err = encoder.Encode(assets)
	if err != nil {
		slog.Log(ctx, slog.LevelError, "json encode failed", "err", err)
	}
}

func (s *Server) refreshAssets(ctx context.Context, chain string, address string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer func() {
		_ = tx.Rollback()
	}()

	nfts, err := s.fetchNFTs(chain, address)
	if err != nil {
		return fmt.Errorf("fetch nfts: %w", err)
	}

	tokens, err := s.fetchTokens(chain, address)
	if err != nil {
		return fmt.Errorf("fetch tokens: %w", err)
	}

	assets := Assets{
		Tokens: tokens,
		NFTs:   nfts,
	}

	assetsJSON, err := json.Marshal(assets)
	if err != nil {
		return fmt.Errorf("marshal asssets: %w", err)
	}

	_, err = tx.Exec(`
			INSERT INTO assets (
				chain,
				address,
				assets
			) VALUES (
				$1,
				$2,
				$3
			)
		`, chain, address, assetsJSON)
	if err != nil {
		return fmt.Errorf("insert new nfts: %w", err)
	}

	err = tx.Commit()
	if err != nil {
		return fmt.Errorf("commit: %w", err)
	}

	return nil
}

func (s *Server) refreshHandler(w http.ResponseWriter, r *http.Request) {
	setCORS(w)
	ctx := r.Context()

	chain := r.PathValue("chain")
	address := r.PathValue("address")
	slog.Log(
		ctx,
		slog.LevelInfo,
		"asset handler",
		"chain", chain,
		"address", address,
	)

	if ok := validateChain(w, chain); !ok {
		return
	}

	if ok := validateAddress(w, address); !ok {
		return
	}

	err := s.refreshAssets(ctx, chain, address)
	if err != nil {
		slog.Log(ctx, slog.LevelError, "refresh assets failed", "err", err)

		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintln(w, "Internal Server Error")

		return
	}

	w.WriteHeader(http.StatusOK)
	fmt.Fprintln(w, "OK")
}

func setCORS(w http.ResponseWriter) {
	header := w.Header()
	header.Set("Access-Control-Allow-Origin", "*")
	header.Set("Access-Control-Allow-Methods", "GET, OPTIONS")
}

func corsHandler(w http.ResponseWriter, _ *http.Request) {
	setCORS(w)

	w.WriteHeader(http.StatusOK)
}

func (s *Server) migrateDB(ctx context.Context) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}

	_, err = tx.Exec(`
		CREATE TABLE IF NOT EXISTS assets (
			chain TEXT NOT NULL,
			address TEXT NOT NULL,
			assets BLOB
		) STRICT;

		CREATE INDEX ON assets (chain, address);
	`)
	if err != nil {
		return fmt.Errorf("create assets table: %w", err)
	}

	return nil
}

func runAPI(ctx context.Context, cmd *cli.Command) error {
	apiAddress := cmd.String("api-addr")
	moralisAPIToken := cmd.String("moralis-api-token")

	database, err := sql.Open("sqlite", "pwn.sqlite")
	if err != nil {
		return fmt.Errorf("opening database: %w", err)
	}

	server := Server{
		moralisAPIToken: moralisAPIToken,
		db:              database,
	}

	err = server.migrateDB(ctx)
	if err != nil {
		return fmt.Errorf("migrate database: %w", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("OPTIONS /", corsHandler)
	mux.HandleFunc("GET /api/assets/{network}/{address}", server.assetsHandler)
	mux.HandleFunc("GET /api/assets/{network}/{address}/refresh", server.refreshHandler)

	slog.Log(ctx, slog.LevelInfo, "starting api", "addr", apiAddress)
	return http.ListenAndServe(apiAddress, mux)
}

func main() {
	err := app.Run(context.Background(), os.Args)
	if err != nil {
		slog.Log(context.Background(), slog.LevelError, "api failed", "err", err)
	}
}
