package main

import (
	"io"
	"net/http"
	"os"
	"sync"
	"time"

	"github.com/bedrock-tool/bedrocktool/utils"
	"github.com/rifflock/lfshook"
	"github.com/sirupsen/logrus"
)

type logFileWriter struct {
	w io.Writer
}

func (l logFileWriter) Write(b []byte) (int, error) {
	if utils.LogOff {
		return len(b), nil
	}
	return l.w.Write(b)
}

// flushLogs closes the stdout pipe and waits until everything written to it reached the real stdout and the
// log file. Without it, output printed right before exit (help, list-realms …) is lost when stdout is a pipe
// (e.g. when CML runs the CLI). Set by setupLogging.
var flushLogs = func() {}

func setupLogging(isDebug bool) {
	logFile, err := os.Create(utils.PathData("bedrocktool.log"))
	if err != nil {
		logrus.Fatal(err)
	}

	rOut, wOut, err := os.Pipe()
	if err != nil {
		logrus.Fatal(err)
	}

	originalStdout := os.Stdout
	logWriter := logFileWriter{w: logFile}
	copied := make(chan struct{})
	go func() {
		m := io.MultiWriter(originalStdout, logWriter)
		io.Copy(m, rOut)
		close(copied)
	}()
	var flushOnce sync.Once
	flushLogs = func() {
		flushOnce.Do(func() {
			wOut.Close()
			select {
			case <-copied:
			case <-time.After(2 * time.Second):
			}
		})
	}

	os.Stdout = wOut
	redirectStderr(wOut)

	logrus.SetLevel(logrus.DebugLevel)
	if isDebug {
		logrus.SetLevel(logrus.TraceLevel)
	}
	logrus.SetOutput(originalStdout)
	logrus.AddHook(lfshook.NewHook(logFile, &logrus.TextFormatter{
		DisableColors: true,
	}))
}

type logTransport struct {
	rt http.RoundTripper
}

func (t *logTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	logrus.Tracef("Request %s", req.URL.String())
	return t.rt.RoundTrip(req)
}
