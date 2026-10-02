package world

import (
	"fmt"

	"github.com/df-mc/dragonfly/server/block/cube"
)

// Feature is a feature that can be placed into the world.
type Feature interface {
	// Name is the name this feature can be looked up as in the registry.
	Name() string
	// CanPlace checks if the feature can be built at this location.
	CanPlace(pos cube.Pos, tx *Tx) bool
	// Place tries to place the feature at the position, returns false if it fails.
	Place(pos cube.Pos, tx *Tx) bool
}

var features = make(map[string]Feature)

// RegisterFeature adds a feature to the registry
func RegisterFeature(f Feature) {
	if _, exists := features[f.Name()]; exists {
		panic(fmt.Sprintf("feature %s already registered", f.Name()))
	}
	features[f.Name()] = f
}

// GetFeature returns a Feature from the registry, returns nil if not found
func GetFeature(name string) Feature {
	return features[name]
}
