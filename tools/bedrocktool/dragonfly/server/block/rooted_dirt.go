package block

import (
	"github.com/df-mc/dragonfly/server/block/cube"
	"github.com/df-mc/dragonfly/server/item"
	"github.com/df-mc/dragonfly/server/world"
	"github.com/df-mc/dragonfly/server/world/particle"
)

// RootedDirt is a natural decorative block that can generate under azalea trees.
type RootedDirt struct {
	solid
}

// SoilFor ...
func (r RootedDirt) SoilFor(block world.Block) bool {
	switch block.(type) {
	case Flower, DoubleFlower, NetherSprouts, SugarCane, Azalea, Sapling:
		return true
	}
	return false
}

// BreakInfo ...
func (r RootedDirt) BreakInfo() BreakInfo {
	return newBreakInfo(0.5, alwaysHarvestable, shovelEffective, oneOf(r))
}

// Till ...
func (r RootedDirt) Till(tx *world.Tx, pos cube.Pos) (world.Block, bool) {
	tx.AddParticle(pos.Vec3Centre(), particle.BlockBreak{Block: r})
	dropItem(tx, item.NewStack(HangingRoots{}, 1), pos.Vec3Centre())
	return Dirt{}, true
}

// BoneMeal ...
func (r RootedDirt) BoneMeal(pos cube.Pos, tx *world.Tx) (success bool) {
	pos2 := pos.Side(cube.FaceDown)
	if _, ok := tx.Block(pos2).(Air); !ok {
		return false
	}
	tx.SetBlock(pos2, HangingRoots{}, nil)
	return true
}

// EncodeItem ...
func (r RootedDirt) EncodeItem() (name string, meta int16) {
	return "minecraft:dirt_with_roots", 0
}

// EncodeBlock ...
func (r RootedDirt) EncodeBlock() (string, map[string]any) {
	return "minecraft:dirt_with_roots", nil
}
