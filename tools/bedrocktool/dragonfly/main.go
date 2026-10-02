package main

import (
	"fmt"
	"os"

	"log/slog"

	"github.com/df-mc/dragonfly/server"
	"github.com/df-mc/dragonfly/server/block/cube"
	"github.com/df-mc/dragonfly/server/player/chat"
	"github.com/df-mc/dragonfly/server/world"
	"github.com/df-mc/dragonfly/server/world/chunk"
	"github.com/pelletier/go-toml"
	"github.com/thomaso-mirodin/intmath/i32"
)

type debugGenerator struct{}

// GenerateChunk ...
func (debugGenerator) GenerateChunk(cp world.ChunkPos, chunk *chunk.Chunk) {
	blockCount := world.DefaultBlockRegistry.BlockCount()
	length := i32.Sqrt(int32(blockCount))

	for x := uint8(0); x < 16; x++ {
		for z := uint8(0); z < 16; z++ {
			X := cp.X()*16 + int32(x)
			Z := cp.Z()*16 + int32(z)
			if X%2 == 0 || Z%2 == 0 {
				continue
			}
			X /= 2
			Z /= 2
			if Z > length {
				continue
			}
			if X > length || X < 0 {
				continue
			}
			rid := (X + Z*length)
			if rid < 0 || rid >= int32(blockCount) {
				continue
			}

			chunk.SetBlock(x, int16(chunk.Range()[0])+1, z, 0, uint32(rid))
		}
	}
}

func (debugGenerator) DefaultSpawn(world.Dimension) cube.Pos {
	return cube.Pos{}
}

func main() {
	slog.SetLogLoggerLevel(slog.LevelDebug)
	chat.Global.Subscribe(chat.StdoutSubscriber{})
	conf, err := readConfig(slog.Default())
	if err != nil {
		panic(err)
	}

	conf.Generator = func(dim world.Dimension) world.Generator {
		return debugGenerator{}
	}

	srv := conf.New()
	srv.CloseOnProgramEnd()

	srv.Listen()
	for p := range srv.Accept() {
		_ = p
	}
}

// readConfig reads the configuration from the config.toml file, or creates the
// file if it does not yet exist.
func readConfig(log *slog.Logger) (server.Config, error) {
	c := server.DefaultConfig()
	var zero server.Config
	if _, err := os.Stat("config.toml"); os.IsNotExist(err) {
		data, err := toml.Marshal(c)
		if err != nil {
			return zero, fmt.Errorf("encode default config: %v", err)
		}
		if err := os.WriteFile("config.toml", data, 0644); err != nil {
			return zero, fmt.Errorf("create default config: %v", err)
		}
		return c.Config(log)
	}
	data, err := os.ReadFile("config.toml")
	if err != nil {
		return zero, fmt.Errorf("read config: %v", err)
	}
	if err := toml.Unmarshal(data, &c); err != nil {
		return zero, fmt.Errorf("decode config: %v", err)
	}
	return c.Config(log)
}
