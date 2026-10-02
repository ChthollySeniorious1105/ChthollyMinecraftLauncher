package signaling

import (
	"context"
	"encoding/json"
	"log/slog"
	"net"
	"sync"
	"sync/atomic"
	"time"

	"github.com/bedrock-tool/bedrocktool/utils/franchise/internal"
	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
	"github.com/df-mc/go-nethernet"
)

// Conn implements a [nethernet.Signaling] over a WebSocket connection.
//
// A Conn may be established using the methods of Dialer with either
// a [franchise.IdentityProvider] and an [Environment] or an [oauth2.TokenSource]
// for authorization.
//
// A Conn can be utilized with [nethernet.ListenConfig.Listen] or [nethernet.Dialer.DialContext].
type Conn struct {
	conn   *websocket.Conn
	d      Dialer
	ctx    context.Context
	cancel context.CancelCauseFunc

	credentials         atomic.Pointer[nethernet.Credentials]
	credentialsReceived chan struct{}

	once   sync.Once
	closed chan struct{}

	notifyCount uint32
	notifiers   map[uint32]nethernet.Notifier
	notifiersMu sync.Mutex
}

var _ nethernet.Signaling = (*Conn)(nil)

// Signal sends a [nethernet.Signal] to a network.
func (c *Conn) Signal(ctx context.Context, signal *nethernet.Signal) error {
	select {
	case <-ctx.Done():
		return context.Cause(ctx)
	case <-c.ctx.Done():
		return context.Cause(c.ctx)
	default:
	}
	return c.write(ctx, Message{
		Type: MessageTypeSignal,
		To:   NetworkID(signal.NetworkID),
		Data: signal.String(),
	})
}

// Notify registers a [nethernet.Notifier] to receive notifications of signals. It returns
// a function to stop receiving notifications on the [nethernet.Notifier].
func (c *Conn) Notify(n nethernet.Notifier) (stop func()) {
	c.notifiersMu.Lock()
	i := c.notifyCount
	c.notifiers[i] = n
	c.notifyCount++
	c.notifiersMu.Unlock()

	return c.stopFunc(i)
}

// stopFunc returns a function to be returned by [Conn.Notify], which stops receiving notifications
// on the Notifier by unregistering it from the Conn.
func (c *Conn) stopFunc(i uint32) func() {
	return sync.OnceFunc(func() {
		c.notifiersMu.Lock()
		delete(c.notifiers, i)
		c.notifiersMu.Unlock()
	})
}

// Context returns a context that is canceled when the Conn is closed or the
// signaling server reports a fatal error.
func (c *Conn) Context() context.Context {
	return c.ctx
}

// Credentials blocks until [nethernet.Credentials] are received from the server or the [context.Context]
// is done. It returns a [nethernet.Credentials] or an error if the Conn is closed or the [context.Context]
// is canceled or exceeded a deadline.
func (c *Conn) Credentials(ctx context.Context) (*nethernet.Credentials, error) {
	if credentials := c.credentials.Load(); credentials != nil {
		return credentials, nil
	}
	select {
	case <-c.credentialsReceived:
		return c.credentials.Load(), nil
	case <-c.closed:
		return nil, context.Cause(c.ctx)
	case <-ctx.Done():
		return nil, context.Cause(ctx)
	}
}

// NetworkID returns the network ID of the Conn. It may be specified from [Dialer.NetworkID], otherwise a random
// value will be automatically set from [rand.Uint64] in set up during [Dialer.DialContext]. It is utilized by
// [nethernet.Listener] and [nethernet.Dialer] to obtain its local network ID to listen.
func (c *Conn) NetworkID() string {
	return c.d.NetworkID
}

func (c *Conn) PongData([]byte) {
}

// Close closes the Conn and unregisters any notifiers. It ensures that the Conn is closed only once.
func (c *Conn) Close() (err error) {
	c.once.Do(func() {
		c.cancel(net.ErrClosed)

		c.notifiersMu.Lock()
		clear(c.notifiers)
		c.notifiersMu.Unlock()

		close(c.closed)
		err = c.conn.Close(websocket.StatusNormalClosure, "")
	})
	return err
}

// read continuously reads messages from the WebSocket connection and handles them.
// It also sends a Message of MessageTypePing at 15 seconds intervals to keep the
// Conn alive. It goes as a background goroutine of the Conn and handles different
// types of messages: credentials, signals, and errors. It closes the Conn if it
// encounters an error or when the Conn is closed.
func (c *Conn) read() {
	go func() {
		ticker := time.NewTicker(time.Second * 15)
		defer ticker.Stop()

		for {
			select {
			case <-c.closed:
				return
			case <-ticker.C:
				if err := c.write(c.ctx, Message{
					Type: MessageTypePing,
				}); err != nil {
					c.d.Log.Error("error writing ping", internal.ErrAttr(err))
					return
				}
			}
		}
	}()
	defer c.Close()

	for {
		var message Message
		if err := wsjson.Read(context.Background(), c.conn, &message); err != nil {
			c.cancel(err)
			return
		}
		switch message.Type {
		case MessageTypeCredentials:
			if message.From != NetworkID("Server") {
				c.d.Log.Warn("received credentials from non-Server", slog.Any("message", message))
				continue
			}
			var credentials nethernet.Credentials
			if err := json.Unmarshal([]byte(message.Data), &credentials); err != nil {
				c.d.Log.Error("error decoding credentials", internal.ErrAttr(err))
				continue
			}
			notifyCredentials := c.credentials.Load() == nil
			c.credentials.Store(&credentials)
			if notifyCredentials {
				close(c.credentialsReceived)
			}
		case MessageTypeSignal:
			signal := &nethernet.Signal{}
			if err := signal.UnmarshalText([]byte(message.Data)); err != nil {
				c.d.Log.Error("error decoding signal", internal.ErrAttr(err))
				continue
			}
			signal.NetworkID = string(message.From)

			c.notifiersMu.Lock()
			notifiers := make([]nethernet.Notifier, 0, len(c.notifiers))
			for _, notifier := range c.notifiers {
				notifiers = append(notifiers, notifier)
			}
			c.notifiersMu.Unlock()
			for _, notifier := range notifiers {
				_ = notifier.NotifySignal(signal)
			}
		case MessageTypeError:
			var err Error
			if err2 := json.Unmarshal([]byte(message.Data), &err); err2 != nil {
				c.d.Log.Error("error decoding error", internal.ErrAttr(err2))
				continue
			}

			c.cancel(&err)
			return
		default:
			c.d.Log.Warn("received message for unknown type", slog.Any("message", message))
		}
	}
}

// write encodes the given Message and sends it over the WebSocket connection. An error may be returned if
// the context is canceled or the message could not be sent.
func (c *Conn) write(ctx context.Context, message Message) error {
	return wsjson.Write(ctx, c.conn, message)
}
