package block

// disconnectedProperties returns the default 26.50+ connection state shared
// by panes, bars, fences, and tripwire. The server still computes collision
// and neighbour behaviour locally; these fields keep the runtime state schema
// compatible with the Bedrock 26.50 registry.
func disconnectedProperties() map[string]any {
	return map[string]any{
		"minecraft:connection_north": false,
		"minecraft:connection_east":  false,
		"minecraft:connection_south": false,
		"minecraft:connection_west":  false,
	}
}
