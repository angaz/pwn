package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"

	"github.com/urfave/cli/v3"
)

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

func helloHandler(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
	fmt.Fprintln(w, "Hello, World!")
}

func runAPI(ctx context.Context, cmd *cli.Command) error {
	apiAddress := cmd.String("api-addr")

	mux := http.NewServeMux()
	mux.HandleFunc("/hello", helloHandler)

	slog.Log(ctx, slog.LevelInfo, "starting api", "addr", apiAddress)
	return http.ListenAndServe(apiAddress, mux)
}

func main() {
	err := app.Run(context.Background(), os.Args)
	if err != nil {
		slog.Log(context.Background(), slog.LevelError, "api failed", "err", err)
	}
}
