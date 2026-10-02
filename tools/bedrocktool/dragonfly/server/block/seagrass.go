package block

import (
	"github.com/df-mc/dragonfly/server/block/cube"
	"github.com/df-mc/dragonfly/server/item"
	"github.com/df-mc/dragonfly/server/world"
	"github.com/go-gl/mathgl/mgl64"
)

// Seagrass is a non-solid plant block that generates in all oceans, except frozen oceans.
type Seagrass struct {
	empty
	transparent
	sourceWaterDisplacer

	// Type is the type of seagrass
	Type SeagrassType
}

// canSurvive ...
func (s Seagrass) canSurvive(pos cube.Pos, tx *world.Tx, ignorePartner bool) bool {
	below := tx.Block(pos.Side(cube.FaceDown))
	above := tx.Block(pos.Side(cube.FaceUp))

	if !ignorePartner {
		if s.Type == TopSeagrass() {
			if bottom, ok := below.(Seagrass); ok {
				if bottom.Type != BottomSeagrass() {
					return false
				}
			} else {
				return false
			}
		}

		if s.Type == BottomSeagrass() {
			if top, ok := above.(Seagrass); ok {
				if top.Type != TopSeagrass() {
					return false
				}
			} else {
				return false
			}
		}
	}

	if liquid, ok := tx.Liquid(pos); ok {
		_, is_water := liquid.(Water)
		if !is_water {
			return false
		}
	} else {
		return false
	}

	if s.Type != TopSeagrass() {
		if !below.Model().FaceSolid(pos.Side(cube.FaceDown), cube.FaceUp, tx) {
			return false
		}
	}
	return true
}

// BoneMeal ...
func (s Seagrass) BoneMeal(pos cube.Pos, tx *world.Tx) bool {
	if s.Type != DefaultSeagrass() {
		return false
	}

	above := pos.Side(cube.FaceUp)
	s2 := Seagrass{Type: TopSeagrass()}
	if s2.canSurvive(above, tx, true) {
		s.Type = BottomSeagrass()
		tx.SetBlock(pos, s, nil)
		tx.SetBlock(above, s2, nil)
		return true
	}
	return false
}

// UseOnBlock ...
func (s Seagrass) UseOnBlock(pos cube.Pos, face cube.Face, _ mgl64.Vec3, tx *world.Tx, user item.User, ctx *item.UseContext) bool {
	pos, _, used := firstReplaceable(tx, pos, face, s)
	if !used {
		return false
	}
	if !s.canSurvive(pos, tx, true) {
		return false
	}

	place(tx, pos, s, user, ctx)
	return placed(ctx)
}

// NeighbourUpdateTick ...
func (s Seagrass) NeighbourUpdateTick(pos, _ cube.Pos, tx *world.Tx) {
	if !s.canSurvive(pos, tx, false) {
		tx.SetBlock(pos, nil, nil)
		if s.Type != DefaultSeagrass() {
			var second cube.Pos
			if s.Type == TopSeagrass() {
				second = pos.Side(cube.FaceDown)
			} else if s.Type == BottomSeagrass() {
				second = pos.Side(cube.FaceUp)
			}
			if _, ok := tx.Block(second).(Seagrass); ok {
				tx.SetBlock(second, nil, nil)
			}
		}
	}
}

// HasLiquidDrops ...
func (Seagrass) HasLiquidDrops() bool {
	return true
}

// SideClosed ...
func (Seagrass) SideClosed(cube.Pos, cube.Pos, *world.World) bool {
	return false
}

// BreakInfo ...
func (s Seagrass) BreakInfo() BreakInfo {
	return newBreakInfo(0, alwaysHarvestable, nothingEffective, func(t item.Tool, e []item.Enchantment) (stack []item.Stack) {
		if t == nil || t.ToolType() == item.TypeShears {
			stack = append(stack, item.NewStack(Seagrass{}, 1))
		}
		return stack
	})
}

// FlammabilityInfo ...
func (Seagrass) FlammabilityInfo() FlammabilityInfo {
	return newFlammabilityInfo(0, 0, false)
}

// EncodeItem ...
func (Seagrass) EncodeItem() (name string, meta int16) {
	return "minecraft:seagrass", 0
}

// EncodeBlock ...
func (s Seagrass) EncodeBlock() (string, map[string]any) {
	return "minecraft:seagrass", map[string]any{
		"sea_grass_type": s.Type.String(),
	}
}

func allSeagrass() (c []world.Block) {
	for _, t := range SeagrassTypes() {
		c = append(c, Seagrass{Type: t})
	}
	return
}
