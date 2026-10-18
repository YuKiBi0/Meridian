// Package web embeds the console build. The dist directory is filled by
// scripts/build-console.sh (or the Dockerfile); only .gitkeep is committed.
package web

import (
	"embed"
	"io/fs"
)

//go:embed all:dist
var dist embed.FS

// FS returns the console files rooted at dist.
func FS() fs.FS {
	sub, err := fs.Sub(dist, "dist")
	if err != nil {
		panic(err)
	}
	return sub
}
