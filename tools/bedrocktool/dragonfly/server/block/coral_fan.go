package block

import (
	"math/rand/v2"
	"time"

	"github.com/df-mc/dragonfly/server/block/cube"
	"github.com/df-mc/dragonfly/server/item"
	"github.com/df-mc/dragonfly/server/world"
	"github.com/df-mc/dragonfly/server/world/particle"
	"github.com/go-gl/mathgl/mgl64"
)

// CoralFan is a non-solid block that comes in 5 variants.
type CoralFan struct {
	empty
	transparent
	sourceWaterDisplacer

	// Type is the type of coral of the block.
	Type CoralType
	// Dead is whether the coral is dead.
	Dead bool
	// Hanging is whether this coral is hanging on a wall
	Hanging bool
	// Facing is the direction that the coral fan is facing.
	Facing cube.Direction
}

// UseOnBlock ...
func (c CoralFan) UseOnBlock(pos cube.Pos, face cube.Face, _ mgl64.Vec3, tx *world.Tx, user item.User, ctx *item.UseContext) bool {
	pos, _, used := firstReplaceable(tx, pos, face, c)
	if !used {
		return false
	}
	if face == cube.FaceDown {
		return false
	}
	if face != cube.FaceUp {
		c.Hanging = true
		c.Facing = cube.Direction(face - 2)
	}
	attach := pos.Side(face)
	if !tx.Block(attach).Model().FaceSolid(attach, face.Opposite(), tx) {
		return false
	}
	if liquid, ok := tx.Liquid(pos); ok {
		if water, ok := liquid.(Water); ok {
			if water.Depth != 8 {
				return false
			}
		} else {
			return false
		}
	} else {
		c.Dead = true
	}

	place(tx, pos, c, user, ctx)
	return placed(ctx)
}

// HasLiquidDrops ...
func (c CoralFan) HasLiquidDrops() bool {
	return false
}

// SideClosed ...
func (c CoralFan) SideClosed(cube.Pos, cube.Pos, *world.World) bool {
	return false
}

// NeighbourUpdateTick ...
func (c CoralFan) NeighbourUpdateTick(pos, _ cube.Pos, tx *world.Tx) {
	var face cube.Face
	if c.Hanging {
		face = c.Facing.Face()
	} else {
		face = cube.FaceDown
	}
	attach := pos.Side(face)
	if !tx.Block(attach).Model().FaceSolid(attach, face.Opposite(), tx) {
		tx.SetBlock(pos, nil, nil)
		tx.AddParticle(pos.Vec3Centre(), particle.BlockBreak{Block: c})
		return
	}
	if c.Dead {
		return
	}
	tx.ScheduleBlockUpdate(pos, c, time.Second*5/2)
}

// ScheduledTick ...
func (c CoralFan) ScheduledTick(pos cube.Pos, tx *world.Tx, _ *rand.Rand) {
	if c.Dead {
		return
	}

	water := false
	if liquid, ok := tx.Liquid(pos); ok {
		if _, ok := liquid.(Water); ok {
			water = true
		}
	}
	if !water {
		c.Dead = true
		tx.SetBlock(pos, c, nil)
	}
}

// BreakInfo ...
func (c CoralFan) BreakInfo() BreakInfo {
	return newBreakInfo(0, alwaysHarvestable, nothingEffective, silkTouchOnlyDrop(c))
}

// EncodeBlock ...
func (c CoralFan) EncodeBlock() (name string, properties map[string]any) {
	name = "minecraft:"
	if c.Dead {
		name += "dead_"
	}
	name += c.Type.String() + "_"
	name += "coral_"
	if c.Hanging {
		name += "wall_"
	}
	name += "fan"

	properties = map[string]any{}
	if c.Hanging {
		properties["coral_direction"] = int32(c.Facing)
	} else {
		switch c.Facing {
		case cube.East, cube.West:
			properties["coral_fan_direction"] = int32(0)
		case cube.North, cube.South:
			properties["coral_fan_direction"] = int32(1)
		}
	}

	return name, properties
}

// EncodeItem ...
func (c CoralFan) EncodeItem() (name string, meta int16) {
	name = "minecraft:"
	if c.Dead {
		name += "dead_"
	}
	name += c.Type.String() + "_"
	name += "coral_"
	if c.Hanging {
		name += "wall_"
	}
	name += "fan"

	if c.Hanging {
		meta |= int16(c.Facing) << 4
	} else {
		switch c.Facing {
		case cube.North, cube.South:
			meta |= int16(1) << 8
		}
	}
	return name, meta
}

// allCoral returns a list of all coral block variants
func allCoralFan() (c []world.Block) {
	f := func(dead bool) {
		for _, t := range CoralTypes() {
			c = append(c, CoralFan{Type: t, Dead: dead})
			for _, d := range cube.Directions() {
				c = append(c, CoralFan{
					Type:    t,
					Dead:    dead,
					Hanging: true,
					Facing:  d,
				})
			}
		}
	}
	f(true)
	f(false)
	return
}
