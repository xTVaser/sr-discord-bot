#  Gemfile plugins
require 'dotenv'
require 'discordrb'

# Local files
require 'sr_discord_bot/version'
require 'db/psql_database'

Dotenv.load('vars.env')

# Bot Documentation - http://www.rubydoc.info/gems/discordrb

# All code in the gem is namespaced under this module.
module DiscordBot

  # Establish Discord Bot Connection
  bot = Discordrb::Bot.new token: ENV['TOKEN'], client_id: ENV['CLIENT_ID']

  bot.ready() do |event|
    event.bot.servers.values.each do |server|
      if server.name == "Dev Server"
        server.text_channels.each do |channel|
          if channel.name == "spam-the-bot"
            channel.send_message("!! Bot Back Online !!")
          end
        end
      end
    end
  end

  bot.message(with_text: 'Bing!') do |event|
    event.respond 'Bing Bong!'
  end
  bot.message(with_text: 'Bing Bing!') do |event|
    event.respond 'Bing Bing Bong Bing!'
  end
  bot.message(with_text: 'Bing Bing Bing!') do |event|
    event.respond 'Bing Bing Bong Bing!'
  end

  # If the bot is connecting to the server for the first time
  # it should establish the database schema, would be nice to
  # not have to call this manually but whatever.

  bot.message(with_text: '!CreateSchema') do |event|
    event.respond "k 1 sec"
    event.respond PostgresDB.generateSchema
    event.respond "finished"
  end

  bot.run
end
