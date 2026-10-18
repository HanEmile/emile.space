package main

import (
	"bufio"
	"crypto/tls"
	"fmt"
	"log"
	"net/textproto"
	"strings"
	"time"
)

const (
	server   = "irc.emile.space:6697"
	channel  = "#general"
	nickname = "go_bot"
)

func main() {
	config := &tls.Config{}
	conn, err := tls.Dial("tcp", server, config)
	if err != nil {
		log.Fatalf("Failed to connect: %v", err)
	}
	defer conn.Close()

	reader := bufio.NewReader(conn)
	tp := textproto.NewReader(reader)

	sendRaw := func(format string, args ...any) {
		msg := fmt.Sprintf(format, args...)
		fmt.Fprintf(conn, "%s\r\n", msg)
		fmt.Printf(">>> %s\n", msg)
	}

	sendRaw("NICK %s", nickname)
	sendRaw("USER %s 0 * :Go IRC Bot", nickname)
	sendRaw("JOIN %s", channel)

	go func() {
		ticker := time.NewTicker(30 * time.Second) // Adjust interval here
		defer ticker.Stop()

		for range ticker.C {
			sendRaw("PRIVMSG %s :Periodic tick: %s", channel, time.Now().Format("15:04:05"))
		}
	}()

	fmt.Println("Bot running. Listening for events...")
	for {
		line, err := tp.ReadLine()
		if err != nil {
			log.Printf("Disconnected from server: %v", err)
			break
		}
		fmt.Printf("<<< %s\n", line)

		if strings.HasPrefix(line, "PING ") {
			sendRaw("PONG %s", line[5:])
			continue
		}

		if strings.Contains(line, "PRIVMSG") {
			parts := strings.SplitN(line, "PRIVMSG "+channel+" :", 2)
			if len(parts) < 2 {
				continue
			}

			messageText := strings.TrimSpace(parts[1])
			cmd, msg, _ := strings.Cut(messageText, " ")

			switch cmd {
			case "!hello":
				sendRaw("PRIVMSG %s :Hello! I am a lightweight Go bot.", channel)
			case "!time":
				sendRaw("PRIVMSG %s :%s", channel, time.Now().Format("15:04:05"))
			case "!echo":
				sendRaw("PRIVMSG %s :%s", channel, msg)
			}
		}
	}
}
