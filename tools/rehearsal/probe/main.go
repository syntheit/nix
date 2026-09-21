// Command rehearsal-probe reads a NanoMDM file store through the storage
// package of the NanoMDM version it is compiled into, and prints counts.
//
// NanoMDM v0.6 and v0.9 have no read-only API that lists enrollments: their
// routes are /mdm (device-authenticated), /version, and, with an API key,
// /v1/pushcert (upload), /v1/push (APNs), /v1/enqueue (writes the queue),
// /v1/escrowkeyunlock (calls Apple) and /migration (writes). So the rehearsal
// compiles this file into each version's own source tree, next to its
// cmd/nanomdm, and calls only the storage methods that read:
// RetrieveMigrationCheckins (how nano2nano enumerates a store),
// RetrievePushInfo, RetrieveTokenUpdateTally, RetrieveBootstrapToken,
// RetrieveNextCommand and RetrievePushCert. The same source compiles
// against both versions.
//
// It prints key=value counts and a push certificate expiry date. It never
// prints an enrollment ID, a file's contents, a token, a key or an error
// text, because an error from a plist decoder can quote the input.
package main

import (
	"context"
	"crypto/x509"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/micromdm/nanomdm/mdm"
	"github.com/micromdm/nanomdm/storage/file"
)

func main() {
	dsn := flag.String("storage-dsn", "", "path of the NanoMDM file store to read (a copy)")
	flag.Parse()
	if *dsn == "" {
		fmt.Fprintln(os.Stderr, "rehearsal-probe: -storage-dsn is required")
		os.Exit(2)
	}
	// file.New creates a missing directory. Refuse instead, so a wrong
	// path reads as a failure rather than as an empty store.
	if fi, err := os.Stat(*dsn); err != nil || !fi.IsDir() {
		fmt.Fprintln(os.Stderr, "rehearsal-probe: -storage-dsn is not an existing directory")
		os.Exit(2)
	}
	s, err := file.New(*dsn)
	if err != nil {
		fmt.Fprintln(os.Stderr, "rehearsal-probe: opening the store failed")
		os.Exit(1)
	}
	ctx := context.Background()
	counts := map[string]int{}
	var failed bool
	bad := func(key string) { counts[key]++; failed = true }

	// Every enrollment, as the storage package itself enumerates them.
	ch := make(chan interface{})
	var enumErr error
	go func() {
		enumErr = s.RetrieveMigrationCheckins(ctx, ch)
		close(ch)
	}()
	for m := range ch {
		switch v := m.(type) {
		case *mdm.Authenticate:
			counts["enumerate.authenticate"]++
		case *mdm.TokenUpdate:
			// Both versions send some TokenUpdates twice (v0.6 sends a
			// device's again in its user-channel pass; v0.9 sends a user
			// channel's in its device pass), so this count differs by
			// version and is informational only.
			counts["enumerate.tokenupdate"]++
		case error:
			// An enrollment that authenticated but never sent a
			// TokenUpdate is sent as a missing-file error by both
			// versions. That is a normal half-finished enrollment, not
			// an unreadable store; any other error is.
			if errors.Is(v, os.ErrNotExist) {
				counts["enumerate.missing-file"]++
			} else {
				bad("enumerate.errors")
			}
		default:
			counts["enumerate.other"]++
		}
	}
	if enumErr != nil {
		bad("enumerate.errors")
	}

	// Per enrollment directory. A directory is an enrollment when it
	// holds an Authenticate (device channel) or a TokenUpdate (either).
	entries, err := os.ReadDir(*dsn)
	if err != nil {
		bad("readdir.errors")
	}
	var topics []string
	for _, e := range entries {
		name := e.Name()
		if !e.IsDir() {
			if strings.HasSuffix(name, ".pem") {
				topic := strings.TrimSuffix(name, ".pem")
				if _, err := os.Stat(filepath.Join(*dsn, topic+".key")); err == nil {
					topics = append(topics, topic)
				}
			}
			continue
		}
		dir := filepath.Join(*dsn, name)
		_, authErr := os.Stat(filepath.Join(dir, file.AuthenticateFilename))
		_, tokErr := os.Stat(filepath.Join(dir, file.TokenUpdateFilename))
		if authErr != nil && tokErr != nil {
			counts["dirs.not-enrollment"]++
			continue
		}
		if authErr == nil {
			counts["enrollments.device"]++
		} else {
			counts["enrollments.user"]++
		}
		r := &mdm.Request{EnrollID: &mdm.EnrollID{ID: name}}

		if tokErr == nil {
			push, err := s.RetrievePushInfo(ctx, []string{name})
			switch {
			case err != nil:
				bad("pushinfo.errors")
			case push[name] != nil:
				counts["pushinfo.ok"]++
			default:
				bad("pushinfo.errors")
			}
		}
		if _, err := s.RetrieveTokenUpdateTally(ctx, name); err != nil {
			bad("tally.errors")
		}
		bst, err := s.RetrieveBootstrapToken(r, nil)
		switch {
		case err != nil && errors.Is(err, os.ErrNotExist):
			counts["bootstraptoken.absent"]++
		case err != nil:
			bad("bootstraptoken.errors")
		case bst != nil && len(bst.BootstrapToken) > 0:
			counts["bootstraptoken.present"]++
		default:
			counts["bootstraptoken.absent"]++
		}
		cmd, err := s.RetrieveNextCommand(r, false)
		switch {
		case err != nil:
			bad("queue.errors")
		case cmd != nil:
			counts["queue.pending"]++
		}
	}

	counts["pushcert.found"] = len(topics)
	var earliest string
	for _, topic := range topics {
		cert, _, err := s.RetrievePushCert(ctx, topic)
		if err != nil || cert == nil || len(cert.Certificate) == 0 {
			bad("pushcert.errors")
			continue
		}
		leaf, err := x509.ParseCertificate(cert.Certificate[0])
		if err != nil {
			bad("pushcert.errors")
			continue
		}
		counts["pushcert.ok"]++
		if d := leaf.NotAfter.UTC().Format("2006-01-02"); earliest == "" || d < earliest {
			earliest = d
		}
	}

	// Always print these, so a zero is visible as a zero.
	for _, k := range []string{"enumerate.errors", "readdir.errors", "pushinfo.errors",
		"tally.errors", "bootstraptoken.errors", "queue.errors", "pushcert.errors",
		"enrollments.device", "enumerate.authenticate", "pushinfo.ok",
		"bootstraptoken.present", "queue.pending", "pushcert.ok"} {
		counts[k] += 0
	}
	keys := make([]string, 0, len(counts))
	for k := range counts {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		fmt.Printf("%s=%d\n", k, counts[k])
	}
	if earliest != "" {
		fmt.Printf("pushcert.notafter=%s\n", earliest)
	}
	if failed {
		os.Exit(1)
	}
}
