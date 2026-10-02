package connectinfo

import (
	"context"
	"errors"
	"fmt"
	"net"
	"path"
	"strconv"
	"strings"

	"github.com/bedrock-tool/bedrocktool/utils/auth"
	"github.com/bedrock-tool/bedrocktool/utils/franchise/gatherings"
	"github.com/google/uuid"
	"github.com/sandertv/gophertunnel/minecraft/realms"
)

type ErrNotFound struct {
	Name string
}

func (e *ErrNotFound) Error() string {
	return fmt.Sprintf("%s not found", e.Name)
}

type ConnectInfo struct {
	Value   string
	Account *auth.Account

	gathering  *gatherings.Gathering
	realm      *realms.Realm
	experience *gatherings.FeaturedServer
}

// Network is the transport used to reach a Minecraft server.
type Network string

const (
	NetworkRakNet    Network = "raknet"
	NetworkNetherNet Network = "nethernet"
	NetworkReplay    Network = "replay"
)

// SignalingProtocol identifies the signaling protocol used for a NetherNet
// destination. Realms using NETHERNET_JSONRPC cannot use the legacy Franchise
// signaling endpoint and message format.
type SignalingProtocol string

const (
	SignalingNone    SignalingProtocol = ""
	SignalingLegacy  SignalingProtocol = "legacy"
	SignalingJSONRPC SignalingProtocol = "jsonrpc"
)

// Target is a fully resolved connection destination. Keeping the transport
// separate from Address prevents opaque NetherNet IDs from being mistaken for
// UDP host:port addresses.
type Target struct {
	Network       Network
	Address       string
	Signaling     SignalingProtocol
	SignalingHost string
}

func (t Target) String() string {
	switch {
	case t.Network == NetworkNetherNet && t.Signaling == SignalingJSONRPC:
		return "nethernet-jsonrpc:" + t.Address
	case t.Network == NetworkNetherNet:
		return "nethernet:" + t.Address
	default:
		return t.Address
	}
}

func (c *ConnectInfo) getGathering(ctx context.Context, name string) (*gatherings.Gathering, error) {
	if c.gathering != nil && c.gathering.Title == name {
		return c.gathering, nil
	}
	gatheringsService, err := c.Account.Gatherings(ctx)
	if err != nil {
		return nil, err
	}
	mcToken, err := c.Account.MCToken(ctx)
	if err != nil {
		return nil, err
	}
	gatherings, err := gatheringsService.GetGatherings(ctx, mcToken)
	if err != nil {
		return nil, err
	}
	for _, gathering := range gatherings {
		title := strings.ToLower(gathering.Title)
		id := strings.ToLower(gathering.GatheringID)
		if strings.HasPrefix(title, name) || strings.HasPrefix(id, name) {
			return gathering, nil
		}
	}
	return nil, &ErrNotFound{Name: name}
}

func (c *ConnectInfo) getExperience(ctx context.Context, name string) (*gatherings.FeaturedServer, error) {
	if c.experience != nil {
		if c.experience.ExperienceId == name {
			return c.experience, nil
		}
		if strings.EqualFold(c.experience.Name, name) {
			return c.experience, nil
		}
	}
	gatherings, err := c.Account.Gatherings(ctx)
	if err != nil {
		return nil, err
	}
	mcToken, err := c.Account.MCToken(ctx)
	if err != nil {
		return nil, err
	}
	featuredServers, err := gatherings.GetFeaturedServers(ctx, mcToken)
	if err != nil {
		return nil, err
	}
	for _, experience := range featuredServers {
		if experience.ExperienceId == name || strings.EqualFold(experience.Name, name) {
			c.experience = &experience
			return c.experience, nil
		}
	}
	return nil, &ErrNotFound{Name: name}
}

func (c *ConnectInfo) getRealm(ctx context.Context, name string) (*realms.Realm, error) {
	name = strings.ToLower(name)
	if c.realm != nil && (strings.EqualFold(c.realm.Name, name) || strconv.Itoa(c.realm.ID) == name) {
		return c.realm, nil
	}
	realmList, err := c.Account.Realms().Realms(ctx)
	if err != nil {
		return nil, err
	}
	for _, realm := range realmList {
		lowerName := strings.ToLower(realm.Name)
		if strings.HasPrefix(lowerName, name) || strconv.Itoa(realm.ID) == name {
			c.realm = &realm
			return c.realm, nil
		}
	}
	return nil, &ErrNotFound{Name: name}
}

func (c *ConnectInfo) Name(ctx context.Context) (string, error) {
	info, err := parseConnectInfo(c.Value)
	if err != nil {
		return "", nil
	}
	if info.netherNet != "" {
		return info.netherNet, nil
	}
	if info.serverAddress != "" {
		host, port, err := net.SplitHostPort(info.serverAddress)
		if err != nil {
			host = info.serverAddress
		} else if port != "19132" {
			host += "_" + port
		}

		return host, nil
	}
	if info.replayName != "" {
		return path.Base(info.replayName), nil
	}
	if info.realmName != "" {
		realm, err := c.getRealm(ctx, info.realmName)
		if err != nil {
			return "", err
		}
		return realm.Name, nil
	}
	if info.gatheringName != "" {
		gathering, err := c.getGathering(ctx, info.gatheringName)
		if err != nil {
			return "", err
		}
		return gathering.Title, nil
	}
	if info.experience != "" {
		exp, err := c.getExperience(ctx, info.experience)
		switch {
		case errors.Is(err, &ErrNotFound{}):
			return info.experience, nil
		case err != nil:
			return "", err
		default:
			return exp.Name, nil
		}
	}
	return "invalid", nil
}

// Resolve resolves the selected server to a transport-aware target.
func (c *ConnectInfo) Resolve(ctx context.Context) (Target, error) {
	info, err := parseConnectInfo(c.Value)
	if err != nil {
		return Target{}, err
	}
	if info.netherNet != "" {
		return Target{
			Network:   NetworkNetherNet,
			Address:   info.netherNet,
			Signaling: info.netherNetSignaling,
		}, nil
	}
	if info.serverAddress != "" {
		return Target{Network: NetworkRakNet, Address: info.serverAddress}, nil
	}
	if info.replayName != "" {
		return Target{Network: NetworkReplay, Address: info.replayName}, nil
	}
	if info.realmName != "" {
		realm, err := c.getRealm(ctx, info.realmName)
		if err != nil {
			return Target{}, err
		}
		address, err := realm.Address(ctx)
		if err != nil {
			return Target{}, err
		}
		return targetForRealmAddress(address)
	}
	if info.gatheringName != "" {
		gathering, err := c.getGathering(ctx, info.gatheringName)
		if err != nil {
			return Target{}, err
		}
		mcToken, err := c.Account.MCToken(ctx)
		if err != nil {
			return Target{}, err
		}
		address, err := gathering.ConnectionAddress(ctx, mcToken)
		if err != nil {
			return Target{}, err
		}
		return targetForFranchiseAddress(address)
	}

	if info.experience != "" {
		expId, err := uuid.Parse(info.experience)
		if err != nil {
			experience, err := c.getExperience(ctx, info.experience)
			if err != nil {
				return Target{}, err
			}
			expId, err = uuid.Parse(experience.ExperienceId)
			if err != nil {
				return Target{}, err
			}
		}
		gatheringsService, err := c.Account.Gatherings(ctx)
		if err != nil {
			return Target{}, err
		}
		mcToken, err := c.Account.MCToken(ctx)
		if err != nil {
			return Target{}, err
		}
		address, err := gatheringsService.JoinExperience(ctx, mcToken, expId)
		if err != nil {
			return Target{}, fmt.Errorf("JoinExperience: %w", err)
		}
		return targetForFranchiseAddress(address)
	}
	return Target{}, errors.New("invalid address")
}

// Address resolves a destination and returns a printable representation. New
// connection code should use Resolve so the network and signaling protocol are
// not discarded.
func (c *ConnectInfo) Address(ctx context.Context) (string, error) {
	target, err := c.Resolve(ctx)
	if err != nil {
		return "", err
	}
	return target.String(), nil
}

func targetForRealmAddress(address realms.RealmAddress) (Target, error) {
	return targetForNetworkAddress(address.Address, address.NetworkProtocol, address.SessionRegionData.RegionName)
}

func targetForFranchiseAddress(address gatherings.ConnectionAddress) (Target, error) {
	protocol := realms.ParseNetworkProtocol(address.NetworkProtocol)
	resolvedAddress := address.Address
	if (protocol == "" || protocol == realms.NetworkProtocolDefault) && address.Port != 0 {
		if _, _, err := net.SplitHostPort(resolvedAddress); err != nil {
			resolvedAddress = net.JoinHostPort(strings.Trim(resolvedAddress, "[]"), strconv.Itoa(address.Port))
		}
	}
	return targetForNetworkAddress(resolvedAddress, protocol, "")
}

func targetForNetworkAddress(address string, protocol realms.NetworkProtocol, regionName string) (Target, error) {
	if strings.TrimSpace(address) == "" {
		return Target{}, errors.New("server returned an empty address")
	}

	switch realms.ParseNetworkProtocol(string(protocol)) {
	case "", realms.NetworkProtocolDefault:
		return Target{Network: NetworkRakNet, Address: address}, nil
	case realms.NetworkProtocolNetherNet:
		return Target{
			Network:   NetworkNetherNet,
			Address:   address,
			Signaling: SignalingLegacy,
		}, nil
	case realms.NetworkProtocolNetherNetJSONRPC:
		host := "signal.franchise.minecraft-services.net"
		if region := strings.ToLower(strings.TrimSpace(regionName)); region != "" {
			host = "signal-" + region + ".franchise.minecraft-services.net"
		}
		return Target{
			Network:       NetworkNetherNet,
			Address:       address,
			Signaling:     SignalingJSONRPC,
			SignalingHost: host,
		}, nil
	default:
		return Target{}, fmt.Errorf("unsupported server network protocol %q", protocol)
	}
}

func (c *ConnectInfo) IsReplay() bool {
	return pcapRegex.MatchString(c.Value)
}

func (c *ConnectInfo) SetRealm(realm *realms.Realm) {
	c.Value = "realm:" + realm.Name
	c.realm = realm
}

func (c *ConnectInfo) SetGathering(gathering *gatherings.Gathering) {
	c.Value = "gathering:" + gathering.Title
	c.gathering = gathering
}

func (c *ConnectInfo) SetFeaturedServer(server *gatherings.FeaturedServer) {
	if server.ExperienceId != "" {
		c.Value = "experience:" + server.Name
		c.experience = server
	} else {
		c.Value = server.Address
	}
}

type parsedConnectInfo struct {
	gatheringName      string
	realmName          string
	replayName         string
	experience         string
	serverAddress      string
	netherNet          string
	netherNetSignaling SignalingProtocol
}

func parseConnectInfo(value string) (*parsedConnectInfo, error) {
	if gatheringRegex.MatchString(value) {
		p := regexGetParams(gatheringRegex, value)
		input := strings.ToLower(p["Title"])
		return &parsedConnectInfo{gatheringName: input}, nil
	}

	if experienceRegex.MatchString(value) {
		p := regexGetParams(experienceRegex, value)
		return &parsedConnectInfo{experience: p["ID"]}, nil
	}

	// realm
	if realmRegex.MatchString(value) {
		p := regexGetParams(realmRegex, value)
		input := strings.ToLower(p["Name"])
		return &parsedConnectInfo{realmName: input}, nil
	}

	// pcap replay
	if pcapRegex.MatchString(value) {
		p := regexGetParams(pcapRegex, value)
		input := p["Filename"]
		return &parsedConnectInfo{replayName: input}, nil
	}

	// NetherNet IDs are opaque strings. Keep the signaling mode separate from
	// the ID so neither prefix is ever passed to the NetherNet dialer.
	for prefix, signaling := range map[string]SignalingProtocol{
		"nethernet-jsonrpc:": SignalingJSONRPC,
		"nethernet:":         SignalingLegacy,
	} {
		if strings.HasPrefix(strings.ToLower(value), prefix) {
			id := strings.TrimSpace(value[len(prefix):])
			if id == "" {
				return nil, errors.New("nethernet network ID is empty")
			}
			return &parsedConnectInfo{netherNet: id, netherNetSignaling: signaling}, nil
		}
	}

	// normal server dns or ip
	serverAddress := value
	if len(strings.Split(serverAddress, ":")) == 1 {
		serverAddress += ":19132"
	}
	return &parsedConnectInfo{serverAddress: serverAddress}, nil
}
