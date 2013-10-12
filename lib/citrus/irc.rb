require 'citrus/irc/version'
require 'coffeemaker/bot'
require 'em-eventsource'
require 'string-irc'
require 'json'
require 'logger'

module Citrus
  module Irc
    class Client

      attr_reader :host, :port, :channel, :stream_url, :timestamps

      def initialize(host, port, channel, stream_url)
        @host        = host
        @port        = port
        @channel     = channel
        @stream_url  = stream_url
        @timestamps  = Hash.new
      end

      def start
        bot = Coffeemaker::Bot.new(
          irc_host: host,
          irc_port: port,
          nick: 'citrus',
          user: 'citrus',
          logger: Logger.new($stdout)
        )

        source = EM::EventSource.new(stream_url)
        source.message do |event_json|
          event_hash = JSON.load(event_json)
          uuid       = event_hash['build']['uuid']

          if event_hash['kind'] == 'build_started'
            timestamps[uuid] = Time.parse(event_hash['timestamp'])
          else
            status = case event_hash['kind']
                     when 'build_failed'
                       StringIrc.new('FAILED').red
                     when 'build_aborted'
                       StringIrc.new('ABORTED').orange
                     when 'build_succeeded'
                       StringIrc.new('SUCCEEDED').green
                     end

            elapsed_time = Time.parse(event_hash['timestamp']) - timestamps[uuid]
            console_url  = File.join(stream_url.gsub('events', 'builds'), uuid, 'console')
            message      = "Build #{uuid} #{status} in #{elapsed_time} seconds"

            bot.irc.msg(channel, message)
            event_hash['build']['changeset']['commits'].each do |commit|
              bot.irc.msg(channel, "* #{commit['author']}: #{commit['message']}")
            end
            bot.irc.msg(channel, console_url)
          end
        end

        bot.start { |irc| irc.join(channel) }
        source.start
      end

    end
  end
end
