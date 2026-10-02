package block

import (
	"github.com/df-mc/dragonfly/server/block/cube"
	"github.com/df-mc/dragonfly/server/block/model"
	"github.com/df-mc/dragonfly/server/item"
	"github.com/df-mc/dragonfly/server/world"
	"github.com/go-gl/mathgl/mgl64"
)

// Candle is a light source,
// which exists in an uncolored variant and 16 dyed ones.
// Candles can be lit with flint and steel and extinguished by water or by right-clicking.
// They can also be waterlogged, but cannot be lit while waterlogged.
type Candle struct {
	transparent
	sourceWaterDisplacer

	// AdditionalCount is the amount of additional candles clustered together.
	AdditionalCount int
	// Lit is if the candle is on.
	Lit bool
	// Dyed is if the candle has a color
	Dyed bool
	// Colour is the colour of the candle.
	Colour item.Colour
}

func (c Candle) Model() world.BlockModel {
	return model.Candle{Count: c.AdditionalCount + 1}
}

// UseOnBlock ...
func (c Candle) UseOnBlock(pos cube.Pos, face cube.Face, _ mgl64.Vec3, tx *world.Tx, user item.User, ctx *item.UseContext) bool {
	if existing, ok := tx.Block(pos).(Candle); ok {
		if existing.AdditionalCount >= 3 {
			return false
		}
		if c.Dyed != existing.Dyed {
			return false
		}
		if c.Colour != existing.Colour {
			return false
		}

		existing.AdditionalCount++
		place(tx, pos, existing, user, ctx)
		return placed(ctx)
	}

	pos, _, used := firstReplaceable(tx, pos, face, c)
	if !used {
		return false
	}

	place(tx, pos, c, user, ctx)
	return placed(ctx)
}

// Ignite ...
func (c Candle) Ignite(pos cube.Pos, tx *world.Tx) bool {
	if !c.Lit {
		c.Lit = true
		tx.SetBlock(pos, c, nil)
		return true
	}
	return false
}

// HasLiquidDrops ...
func (Candle) HasLiquidDrops() bool {
	return true
}

// SideClosed ...
func (Candle) SideClosed(cube.Pos, cube.Pos, *world.World) bool {
	return false
}

// LightEmissionLevel ...
func (c Candle) LightEmissionLevel() uint8 {
	return uint8(3 + c.AdditionalCount*3)
}

// BreakInfo ...
func (c Candle) BreakInfo() BreakInfo {
	return newBreakInfo(0.1, alwaysHarvestable, nothingEffective, simpleDrops(item.NewStack(c, c.AdditionalCount+1)))
}

// FlammabilityInfo ...
func (Candle) FlammabilityInfo() FlammabilityInfo {
	return newFlammabilityInfo(0, 0, false)
}

// EncodeItem ...
func (c Candle) EncodeItem() (name string, meta int16) {
	name = "minecraft:"
	if c.Dyed {
		if c.Colour == item.ColourLightGrey() {
			name += "light_gray_"
		} else {
			name += c.Colour.String() + "_"
		}
	}
	name += "candle"
	return name, 0
}

// EncodeBlock ...
func (c Candle) EncodeBlock() (name string, data map[string]any) {
	name = "minecraft:"
	if c.Dyed {
		if c.Colour == item.ColourLightGrey() {
			name += "light_gray_"
		} else {
			name += c.Colour.String() + "_"
		}
	}
	name += "candle"
	return name, map[string]any{
		"candles": int32(c.AdditionalCount),
		"lit":     bool(c.Lit),
	}
}

// allCandle ...
func allCandle() (b []world.Block) {
	f := func(lit bool) {
		for i := 0; i <= 3; i++ {
			for _, c := range item.Colours() {
				b = append(b, Candle{
					AdditionalCount: i,
					Lit:             lit,
					Dyed:            true,
					Colour:          c,
				})
			}
			b = append(b, Candle{
				AdditionalCount: i,
				Lit:             lit,
				Dyed:            false,
			})
		}
	}
	f(false)
	f(true)
	return
}
