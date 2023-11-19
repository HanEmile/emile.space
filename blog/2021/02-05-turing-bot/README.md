# Turing bot

:::toc

I've played around a bit with Markov Chains and have found them to be a fun and simple way to generate sentences from existing data. A problem I've had was to actually aquire such data for generating the markov chain. I've used The Entire Bee Movie Script and the updated version of the Gutenberg dataset as an input, but none of there really satisfied me. The sentences end up just being weird and don't really make sense in context.

## Data

That was the moment I realized I needed data, lots of data and it hat to be somehow realistic. The end goal was to build a chatbot you could chat with and get okish responses. Obtaining data is hard, due to throwing all moral understanding overboard being bad habit. The data we need ist the data produced in private chats, so I tried inserting my telegram history into the markov chain, but the result was kind of underwhelming. I didn't really find the right settings for the sentences to be appropriate and it just isn't enough data.

## Removing the bot

Then I had the idea of building a bot people could talk to and use that conversation as data for the markov chain. Problem: this presupposes that such a bot already exists: a contradiction. We can solve this problem by completly eliminating the bot:

I built a small bot that just functions as a gateway connecting two people. The people think that they are talking to a bot, but in the end, they're talking to each other. This led to really interesting conversations and I kind of felt as if I was watching a turing test (I was, but it was kind of surreal).

## Learnings

There were more learnings than "writing a telegram bot is fairly easy": Watching how people talk with each other and unknowingly try to test the limits of bots is super interesting and entertaining at the same time.

## Reactions

> "Ja und bin überrascht wie gut. Mache hauptsächlich Definitionsfragen und kann mir vorstellen, dass da paar klügere Search-Engine-Queries hinterhängen, aber ich konnte auf Englisch wechseln".

> "Yes and I'm surprised how good. I'm mostly asking definition questions and can imagine there are some smarter search engine queries in the backend, but I was able to switch to English"

## Code

The complete code is a bit more than 100 lines of pure code, I've added a lot of comments for making it easier to understand, even for beginners.

Beware: this code was written down in a matter of minutes, there are a lot of things wrong with it (such as everything being in the main function), but it works for a minimal prototype which was the goal of all of this.


> package main
>  
> import (
> 	"fmt"
> 	"log"
> 	"os"
> 	"time"
>  
> 	tgbotapi "github.com/go-telegram-bot-api/telegram-bot-api"
> )
>  
> // Connections is a map storing connections between people
> var Connections map[int64]int64
>  
> // ChatIDPerson maps a chatID to a username
> var ChatIDPerson map[int64]string
>  
> func main() {
> 	// define the bot
> 	bot, err := tgbotapi.NewBotAPI("REDACTED")
> 	if err != nil {
> 		log.Panic(err)
> 		return
> 	}
>  
> 	u := tgbotapi.NewUpdate(0)
> 	u.Timeout = 60
> 	updates, err := bot.GetUpdatesChan(u)
>  
> 	// initialize the connections and the chatidperson map
> 	Connections = make(map[int64]int64)
> 	ChatIDPerson = make(map[int64]string)
> 
> 	// insert the "admin" chatid for recieving notifications when the bot
> 	// starts and getting all the messages
> 	var emile int64 = "REDACTED"
> 
> 	// create a file to log the messages for inserting them into the markov
> 	// chain
> 	f, err := os.Create(fmt.Sprintf("%d.txt", time.Now().UnixNano()))
> 	if err != nil {
> 		log.Panic(err)
> 		return
> 	}
> 
> 	// Intialilize known connections here:
> 	// var alice int64 = 123456
> 	// var bob int64 = 654321
> 	// Connections[alice] = bob
> 	// Connections[bob] = alice
>  
> 	// send the "admin" a message that the bot has started
> 	msg := tgbotapi.NewMessage(emile, "Bot started")
> 	bot.Send(msg)
>  
> 	// print all existing connections and send them to the admin
> 	for sender, reciever := range Connections {
> 		connection := fmt.Sprintf("%s: %s\n", ChatIDPerson[sender], ChatIDPerson[reciever])
> 		fmt.Printf("%s", connection)
> 		msg1 := tgbotapi.NewMessage(emile, connection)
> 		bot.Send(msg1)
> 	}
>  
>  
> 	// this is the "main" loop, we can handle message updates (aka. incomming
> 	// messages) in here
> 	for update := range updates {
> 
> 		// ignore any non-Message Updates
> 		if update.Message == nil {
> 			continue
> 		}
>  
> 		// define shorthands for the chat id the current message is from and
> 		// the message text
> 		chatID := update.Message.Chat.ID
> 		message := update.Message.Text
>  
> 		// don't handle anything except for text messages
> 		if update.Message.Audio != nil || update.Message.Document != nil || update.Message.Photo != nil || update.Message.Sticker != nil || update.Message.Video != nil || update.Message.Voice != nil || update.Message.Contact != nil || update.Message.Location != nil || update.Message.Sticker != nil {
> 			msg1 := tgbotapi.NewMessage(chatID, "ERROR")
> 			bot.Send(msg1)
> 		}
>  
> 		// if the user enters /start, tell them to enter /connect to get connected to another user 
> 		if message == "/start" {
> 			msg1 := tgbotapi.NewMessage(chatID, "Enter /connect to connect to a bot to talk to.")
> 			bot.Send(msg1)
> 		}
>  
> 		// if the users enters /connect, try establishing a connection with
> 		// another user. If no other user is available, wait until another
> 		// user enters /connect to get connected
> 		if message == "/connect" {
> 
> 			// null the own connection, this deletes the connection if the user
> 			// is already connected to another user
> 			partnerID := Connections[chatID]
> 			if Connections[chatID] != 0 {
> 				Connections[partnerID] = 0
> 				msg := tgbotapi.NewMessage(partnerID, "You have been disconnected, enter /connect to talk with another bot.")
> 				bot.Send(msg)
> 			}
>  
> 			// this loop iterates over all connections searching for a person
> 			// that currently has not connection partner, 
> 			var randomChatID int64 = 0
> 			for a, b := range Connections {
> 
> 				// make sure that people don't get connected with themselves or
> 				// their previous connection partner
> 				if a != chatID && a != partnerID && b == 0 {
> 
> 					// if a person is found, inform the user and the connection
> 					// partner that they've been connected
> 					randomChatID = a
> 					msg1 := tgbotapi.NewMessage(randomChatID, "You are now connected to a bot, write something!")
> 					bot.Send(msg1)
> 					msg2 := tgbotapi.NewMessage(chatID, "You are now connected to a bot, write something!")
> 					bot.Send(msg2)
> 				}
> 			}
> 
> 			// if no person was found, the user has to wait until another
> 			// person enters /connect, inform them that this might take a while
> 			if randomChatID == 0 {
> 				msg := tgbotapi.NewMessage(chatID, "I'll notify you as soon as I've got a bot that can talk to you *warteschlangenmusik*.")
> 				bot.Send(msg)
> 			}
> 
> 			// establish the connection between the user and the connection
> 			// partner
> 			Connect(chatID, randomChatID)
> 		}
>  
> 		// if the user has no connection partner and doesn't enter /connect,
> 		// inform them that they can enter /connect in order to be connected
> 		if Connections[chatID] == 0 && message != "/connect" {
> 			msg1 := tgbotapi.NewMessage(chatID, "Enter /connect to connect to a bot to talk to.")
> 			bot.Send(msg1)
> 		}
>  
> 		// if the user has got a connection partner, send their messages there
> 		if Connections[chatID] != 0 && message[0] != '/' {
> 			msg := tgbotapi.NewMessage(Connections[chatID], message)
> 			bot.Send(msg)
> 		}
>  
> 		// also send all messages to the admin, this ist for "moderation", as
> 		// we don't want this to end bad, for more information on the
> 		// problems arising with this, see the "problems" section in the
> 		// blogpost below
> 		formattedMessage := fmt.Sprintf("<%s> %s", update.Message.From.FirstName, message)
> 		msg := tgbotapi.NewMessage(emile, formattedMessage)
> 		bot.Send(msg)
>  
> 		// add the firstname of the person to the mapping from chatid to name
> 		ChatIDPerson[chatID] = update.Message.From.FirstName
>  
> 		// log the messages sent
> 		log.Printf("<%d> [%s]→[%s] %s", update.Message.Chat.ID, update.Message.From.FirstName, ChatIDPerson[Connections[chatID]], update.Message.Text)
>  
> 		// print all connections
> 		for sender, reciever := range Connections {
> 			fmt.Printf("%s: %s\n", ChatIDPerson[sender], ChatIDPerson[reciever])
> 		}
>  
> 		// write the messages to the logfile
> 		_, err := f.WriteString(message + "\n")
> 		if err != nil {
> 			log.Panic(err)
> 			return
> 		}
> 	}
> 	f.Close()
> }
>  
> // Connect a chat to another
> func Connect(chatID int64, otherChatID int64) {
> 	Connections[chatID] = otherChatID
> 	Connections[otherChatID] = chatID
> }