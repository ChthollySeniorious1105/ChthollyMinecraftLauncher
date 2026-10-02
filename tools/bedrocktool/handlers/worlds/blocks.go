package worlds

import (
	"fmt"
	"strings"

	"github.com/df-mc/dragonfly/server/world"
	"github.com/sandertv/gophertunnel/minecraft/protocol"
	"github.com/zaataylor/cartesian/cartesian"
)

var traitLookup = map[string][]any{
	"minecraft:cardinal_direction": {
		"north", "east", "south", "west",
	},
	"minecraft:facing_direction": {
		"north", "east", "south", "west", "down", "up",
	},
	"minecraft:corner_and_cardinal_direction": {
		"inner_left", "inner_right", "outer_left", "outer_right", "none",
	},
	"minecraft:sixteen_way_rotation": {
		"1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15", "16",
	},
	"minecraft:vertical_half": {
		"top", "bottom",
	},
	"minecraft:block_face": {
		"north", "east", "south", "west", "down", "up",
	},
}

func splitNamespace(identifier string) (ns, name string) {
	sp := strings.SplitN(identifier, ":", 2)
	if len(sp) == 1 {
		return "", identifier
	}
	return sp[0], sp[1]
}

func AddCustomBlocks(reg world.BlockRegistry, entries []protocol.BlockEntry) error {
	for _, entry := range entries {
		ns, _ := splitNamespace(entry.Name)
		if ns == "minecraft" {
			continue
		}

		var propertyNames []string
		var propertyValues []any

		props, ok := entry.Properties["properties"].([]any)
		if ok {
			for _, v := range props {
				v := v.(map[string]any)
				name := v["name"].(string)
				enum := v["enum"]
				propertyNames = append(propertyNames, name)
				propertyValues = append(propertyValues, enum)
			}
		}

		traits, ok := entry.Properties["traits"].([]any)
		if ok {
			for _, trait := range traits {
				trait := trait.(map[string]any)
				name := trait["name"].(string)
				switch enabled_states := trait["enabled_states"].(type) {
				case map[string]any:
					for k, enabled := range enabled_states {
						if !strings.ContainsRune(k, ':') {
							k = "minecraft:" + k
						}
						enabled := enabled.(uint8)
						if enabled == 0 {
							continue
						}
						v, ok := traitLookup[k]
						if !ok {
							return fmt.Errorf("unresolved trait %s", k)
						}

						propertyNames = append(propertyNames, k)
						propertyValues = append(propertyValues, v)
					}
				case int32:
					if name == "minecraft:connection" {
						propertyNames = append(propertyNames, "minecraft:connection_north", "minecraft:connection_south", "minecraft:connection_west", "minecraft:connection_east")
						var b = []bool{false, true}
						propertyValues = append(propertyValues, b, b, b, b)
					} else {
						return fmt.Errorf("unresolved trait %s", name)
					}
				}
			}
		}

		permutations := cartesian.NewCartesianProduct(propertyValues).Values()

		for _, values := range permutations {
			m := make(map[string]any)
			for i, value := range values {
				name := propertyNames[i]
				m[name] = value
			}
			reg.RegisterBlockState(world.BlockState{
				Name:       entry.Name,
				Properties: m,
			})
		}
	}

	return nil
}
