package model

import (
	"github.com/df-mc/dragonfly/server/block/cube"
	"github.com/df-mc/dragonfly/server/world"
)

// Candle is a model used by candles.
type Candle struct {
	Count int
}

// BBox returns a single cube.BBox whose size depends on the count of candles.
func (c Candle) BBox(cube.Pos, world.BlockSource) []cube.BBox {
	model := full.Stretch(cube.X, -7/16.0).Stretch(cube.Z, -7/16.0).ExtendTowards(cube.FaceDown, 10/16.0)
	if c.Count == 2 {
		model = model.Stretch(cube.X, 2/16.0).ExtendTowards(cube.FaceWest, 1/16.0)
	}
	if c.Count >= 3 {
		model = model.Stretch(cube.X, 1.5/16).Stretch(cube.Z, 1.5/16)
	}
	return []cube.BBox{model}
}

// FaceSolid always returns false.
func (c Candle) FaceSolid(cube.Pos, cube.Face, world.BlockSource) bool {
	return false
}
