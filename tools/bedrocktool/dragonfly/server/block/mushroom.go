package block

import (
	"math/rand"

	"github.com/df-mc/dragonfly/server/block/cube"
	"github.com/df-mc/dragonfly/server/item"
	"github.com/df-mc/dragonfly/server/world"
	"github.com/go-gl/mathgl/mgl64"
)

// Mushroom is a variety of fungus that grows and spreads in dark areas. Mushrooms generate as red or brown in color
type Mushroom struct {
	empty
	transparent

	Type MushroomType
}

// Grow grows this mushroom into a huge mushroom
func (m Mushroom) Grow(pos cube.Pos, tx *world.Tx) (success bool) {
	feature := world.GetFeature("minecraft:huge_" + m.Type.String() + "_mushroom")
	if feature != nil {
		return feature.Place(pos, tx)
	}
	return false
}

// canSpread checks if theres not more than 5 mushrooms around it
func (m Mushroom) canSpread(pos cube.Pos, tx *world.Tx) bool {
	count := 0
	for x := -4; x <= 4; x++ {
		for y := -1; y <= 1; y++ {
			for z := -4; z <= 4; z++ {
				b := tx.Block(pos.Add(cube.Pos{x, y, z}))
				if other, ok := b.(Mushroom); ok {
					if other.Type == m.Type {
						count++
						if count >= 5 {
							return false
						}
					}
				}
			}
		}
	}
	return count < 5
}

func (m Mushroom) canSurvive(pos cube.Pos, tx *world.Tx) bool {
	below := pos.Side(cube.FaceDown)
	// must be on solid block
	if !tx.Block(below).Model().FaceSolid(below, cube.FaceUp, tx) {
		return false
	}
	// cant be to bright
	if tx.Light(below) >= 13 {
		return false
	}
	// cant be directly in the sky ??? not true ???
	/*
		if pos.Y() < w.HighestBlock(pos.X(), pos.Y()) {
			return false
		}
	*/
	return true
}

// RandomTick ...
func (m Mushroom) RandomTick(pos cube.Pos, tx *world.Tx, r *rand.Rand) {
	if rand.Intn(25) == 0 {
		if m.canSpread(pos, tx) {
			pos2 := pos.Add(cube.Pos{rand.Intn(3) - 1, rand.Intn(2) - rand.Intn(2), rand.Intn(3) - 1})
			m2 := Mushroom{Type: m.Type}
			if m2.canSurvive(pos2, tx) {
				tx.SetBlock(pos2, m2, nil)
			}
		}
	}
}

// BoneMeal ...
func (m Mushroom) BoneMeal(pos cube.Pos, tx *world.Tx) (success bool) {
	if rand.Float64() < 0.4 {
		m.Grow(pos, tx)
	}
	return true
}

// UseOnBlock ...
func (m Mushroom) UseOnBlock(pos cube.Pos, face cube.Face, _ mgl64.Vec3, tx *world.Tx, user item.User, ctx *item.UseContext) bool {
	pos, _, used := firstReplaceable(tx, pos, face, m)
	if !used {
		return false
	}

	if !m.canSurvive(pos, tx) {
		return false
	}

	place(tx, pos, m, user, ctx)
	return placed(ctx)
}

// NeighbourUpdateTick ...
func (m Mushroom) NeighbourUpdateTick(pos, _ cube.Pos, tx *world.Tx) {
	if !m.canSurvive(pos, tx) {
		tx.SetBlock(pos, nil, nil)
	}
}

// HasLiquidDrops ...
func (Mushroom) HasLiquidDrops() bool {
	return true
}

// FlammabilityInfo ...
func (Mushroom) FlammabilityInfo() FlammabilityInfo {
	return newFlammabilityInfo(0, 0, false)
}

// BreakInfo ...
func (m Mushroom) BreakInfo() BreakInfo {
	return newBreakInfo(0, alwaysHarvestable, nothingEffective, oneOf(m))
}

// CompostChance ...
func (Mushroom) CompostChance() float64 {
	return 0.65
}

// EncodeItem ...
func (m Mushroom) EncodeItem() (name string, meta int16) {
	return "minecraft:" + m.Type.String() + "_mushroom", int16(m.Type.Uint8())
}

// EncodeBlock ...
func (m Mushroom) EncodeBlock() (name string, properties map[string]any) {
	return "minecraft:" + m.Type.String() + "_mushroom", properties
}

func allMushroom() (s []world.Block) {
	for _, t := range MushroomTypes() {
		s = append(s, Mushroom{Type: t})
	}
	return
}
