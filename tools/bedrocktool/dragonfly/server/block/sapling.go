package block

import (
	"math/rand"

	"github.com/df-mc/dragonfly/server/block/cube"
	"github.com/df-mc/dragonfly/server/item"
	"github.com/df-mc/dragonfly/server/world"
	"github.com/go-gl/mathgl/mgl64"
)

// Sapling is a non-solid block that can be grown into a tree.
type Sapling struct {
	empty
	transparent

	Wood WoodType

	AgeBit bool
}

// findSaplings finds the same sapling type in a 2x2 area, returns the lowest xz coordinates.
func (s Sapling) findSaplings(pos cube.Pos, tx *world.Tx) (*cube.Pos, bool) {
	validPositions := [][]cube.Pos{
		{pos, pos.Add(cube.Pos{1, 0, 0}), pos.Add(cube.Pos{0, 0, 1}), pos.Add(cube.Pos{1, 0, 1})},
		{pos, pos.Add(cube.Pos{-1, 0, 0}), pos.Add(cube.Pos{0, 0, -1}), pos.Add(cube.Pos{-1, 0, -1})},
		{pos, pos.Add(cube.Pos{1, 0, 0}), pos.Add(cube.Pos{0, 0, -1}), pos.Add(cube.Pos{1, 0, -1})},
		{pos, pos.Add(cube.Pos{-1, 0, 0}), pos.Add(cube.Pos{-1, 0, 0}), pos.Add(cube.Pos{-1, 0, 1})},
	}
	for _, v := range validPositions {
		correct := true
		for _, p := range v {
			if sapling, ok := tx.Block(p).(Sapling); ok {
				if sapling.Wood != s.Wood {
					correct = false
				}
			} else {
				correct = false
			}
		}
		if correct {
			lowestX := 0
			lowestZ := 0
			first := true
			for _, p := range v {
				if p.X() < lowestX || first {
					lowestX = p.X()
				}
				if p.Z() < lowestZ || first {
					lowestZ = p.Z()
				}
				first = false
			}
			return &cube.Pos{lowestX, pos.Y(), lowestZ}, true
		}
	}
	return nil, false
}

// Grow grows this sapling into a tree
func (s Sapling) Grow(pos cube.Pos, tx *world.Tx) (success bool) {
	var tree world.Feature
	pos2, correct := s.findSaplings(pos, tx)
	if correct { // if a large version of this tree exists grow that
		tree = world.GetFeature("minecraft:large_" + s.Wood.String() + "_tree")
		if tree != nil {
			pos = *pos2
		}
	}

	if tree == nil {
		tree = world.GetFeature("minecraft:" + s.Wood.String() + "_tree")
	}

	// check that this tree type exists and can be placed
	if tree != nil && tree.CanPlace(pos, tx) {
		tree.Place(pos, tx)
		return true
	}
	return false
}

// RandomTick ...
func (s Sapling) RandomTick(pos cube.Pos, tx *world.Tx, r *rand.Rand) {
	if rand.Intn(16) == 1 && tx.Light(pos) < 9 {
		return
	}
	s.Grow(pos, tx)
}

// BoneMeal ...
func (s Sapling) BoneMeal(pos cube.Pos, tx *world.Tx) (success bool) {
	s.Grow(pos, tx)
	return true
}

// UseOnBlock ...
func (s Sapling) UseOnBlock(pos cube.Pos, face cube.Face, _ mgl64.Vec3, tx *world.Tx, user item.User, ctx *item.UseContext) bool {
	pos, _, used := firstReplaceable(tx, pos, face, s)
	if !used {
		return false
	}
	if !supportsVegetation(s, tx.Block(pos.Side(cube.FaceDown))) {
		return false
	}

	place(tx, pos, s, user, ctx)
	return placed(ctx)
}

// HasLiquidDrops ...
func (Sapling) HasLiquidDrops() bool {
	return true
}

// FlammabilityInfo ...
func (Sapling) FlammabilityInfo() FlammabilityInfo {
	return newFlammabilityInfo(0, 0, false)
}

// BreakInfo ...
func (s Sapling) BreakInfo() BreakInfo {
	return newBreakInfo(0, alwaysHarvestable, nothingEffective, oneOf(s))
}

// CompostChance ...
func (Sapling) CompostChance() float64 {
	return 0.3
}

// EncodeItem ...
func (s Sapling) EncodeItem() (name string, meta int16) {
	return "minecraft:sapling", int16(s.Wood.Uint8())
}

// EncodeBlock ...
func (s Sapling) EncodeBlock() (name string, properties map[string]any) {
	return "minecraft:sapling", map[string]any{
		"sapling_type": s.Wood.String(),
		"age_bit":      s.AgeBit,
	}
}

func allSapling() (saplings []world.Block) {
	for _, w := range WoodTypes() {
		if w == CrimsonWood() || w == WarpedWood() || w == MangroveWood() || w == CherryWood() {
			continue
		}
		saplings = append(saplings, Sapling{Wood: w})
	}
	return
}
