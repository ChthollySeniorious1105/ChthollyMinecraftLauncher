package block

import (
	"math/rand"

	"github.com/df-mc/dragonfly/server/block/cube"
	"github.com/df-mc/dragonfly/server/item"
	"github.com/df-mc/dragonfly/server/world"
	"github.com/df-mc/dragonfly/server/world/particle"
	"github.com/go-gl/mathgl/mgl64"
)

// Azalea are a flower like block that can grow into an azalea tree.
type Azalea struct {
	solid
	transparent

	// Flowering specifies if this block is flowering.
	Flowering bool
}

// BoneMeal ...
func (a Azalea) BoneMeal(pos cube.Pos, tx *world.Tx) (success bool) {
	if rand.Float64() < 0.45 {
		if _, ok := tx.Block(pos.Side(cube.FaceDown)).(Moss); ok {
			for i := 0; i < 8; i++ {
				p := pos.Add(cube.Pos{rand.Intn(7) - 3, rand.Intn(3) - 1, rand.Intn(7) - 3})
				if _, ok := tx.Block(p).(Air); !ok {
					continue
				}
				if _, ok := tx.Block(p.Side(cube.FaceDown)).(Moss); !ok {
					continue
				}
				tx.SetBlock(p, Azalea{}, nil)
			}
		} else {
			tree := world.GetFeature("minecraft:azalea_tree")
			if tree.CanPlace(pos, tx) {
				return tree.Place(pos, tx)
			}
		}
	}
	return true
}

// NeighbourUpdateTick ...
func (a Azalea) NeighbourUpdateTick(pos, _ cube.Pos, tx *world.Tx) {
	if !supportsVegetation(a, tx.Block(pos.Side(cube.FaceDown))) {
		tx.SetBlock(pos, nil, nil)
		tx.AddParticle(pos.Vec3Centre(), particle.BlockBreak{Block: a})
		dropItem(tx, item.NewStack(a, 1), pos.Vec3Centre())
	}
}

// UseOnBlock ...
func (a Azalea) UseOnBlock(pos cube.Pos, face cube.Face, _ mgl64.Vec3, tx *world.Tx, user item.User, ctx *item.UseContext) bool {
	pos, _, used := firstReplaceable(tx, pos, face, a)
	if !used {
		return false
	}
	down := tx.Block(pos.Side(cube.FaceDown))
	if !supportsVegetation(a, down) {
		return false
	}

	place(tx, pos, a, user, ctx)
	return placed(ctx)
}

// HasLiquidDrops ...
func (Azalea) HasLiquidDrops() bool {
	return true
}

// FlammabilityInfo ...
func (a Azalea) FlammabilityInfo() FlammabilityInfo {
	return newFlammabilityInfo(60, 100, false)
}

// BreakInfo ...
func (a Azalea) BreakInfo() BreakInfo {
	return newBreakInfo(0, alwaysHarvestable, nothingEffective, oneOf(a))
}

// CompostChance ...
func (Azalea) CompostChance() float64 {
	return 0.65
}

// EncodeItem ...
func (a Azalea) EncodeItem() (name string, meta int16) {
	name = "minecraft:"
	if a.Flowering {
		name += "flowering_"
	}
	name += "azalea"
	return name, 0
}

// EncodeBlock ...
func (a Azalea) EncodeBlock() (name string, properties map[string]any) {
	name = "minecraft:"
	if a.Flowering {
		name += "flowering_"
	}
	name += "azalea"
	return name, map[string]any{}
}

// allLogs returns a list of all possible leaves states.
func allAzalea() (leaves []world.Block) {
	f := func(flowering bool) {
		leaves = append(leaves, Azalea{Flowering: flowering})
	}
	f(true)
	f(false)
	return leaves
}
